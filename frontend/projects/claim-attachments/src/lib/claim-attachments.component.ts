import * as AngularCore from '@angular/core';
import * as Rxjs from 'rxjs';
import * as FacetsClient from '@facets-client/common';

import * as ClaimAttachmentsService from './claim-attachments.service';
import * as Interfaces from './claim-attachments.interface';

export const ModuleKey = '19C2807C-9D2A-4F2A-80FE-E330D248C439';

@AngularCore.Component({
  selector: 'lib-claim-attachments',
  templateUrl: './claim-attachments.view.html',
  styleUrls: ['./claim-attachments.styles.scss']
})
export class ClaimAttachmentsComponent implements AngularCore.OnInit, AngularCore.OnDestroy {
  constructor(
    protected loggingService: FacetsClient.LoggingService,
    protected authService: FacetsClient.AuthenticationService,
    protected dataIO: FacetsClient.DataIO,
    protected contextService: FacetsClient.ContextService,
    protected panelEventService: FacetsClient.FacetsPanelEventsService,
    protected cdr: AngularCore.ChangeDetectorRef,
    protected ngZone: AngularCore.NgZone,
    protected configService: FacetsClient.ConfigurationService,
    protected claimAttachmentsService: ClaimAttachmentsService.ClaimAttachmentsService
  ) { }

  protected subscriptions: Rxjs.Subscription[] = [];

  pageLoadError: string | null = null;
  pageLoading = true;
  facetsServicesUri = '';

  // Values redacted/replaced from screenshot for safety.
  private downloadFileUrl = 'https://example-download-url';
  private uploadFileUrl = 'https://example-upload-url';
  private apimSubscriptionKey = '';

  claimData: any = {};
  syinData: any = {};
  atsyData: any = [];
  attachmentData: Interfaces.ClaimAttachment[] = [];

  view: Interfaces.ViewState = {
    open: false,
    loading: false,
    error: '',
    canIframe: false,
    filename: '',
    directory: '',
    iframeBlobUrl: null,
    downloadUrl: null,
    notes: null
  };

  @AngularCore.ViewChild('viewerIframe')
  private viewerIframe?: AngularCore.ElementRef<HTMLIFrameElement>;

  attachmentFormOpen = false;
  attachmentForm: Interfaces.AttachmentForm | null = null;
  attachmentFormSubmitting = false;
  attachmentFormError: string | null = null;

  noteFormOpen = false;
  noteFormAttachment: Interfaces.ClaimAttachment | null = null;
  noteFormSubmitting = false;
  noteFormError: string | null = null;
  newNoteText: string | null = null;

  private attachmentAttbId = 'ATDT';
  private noteAtsyId = 'ATMO';
  private mailAttnType = 'ATMD';
  private ATXRDefaultId = '1753-01-01T00:00:00';

  noteHover = { visible: false, top: 0, left: 0, row: null as any, placement: 'bottom' as 'bottom' | 'top' };

  private readonly iframeAllowListSet = new Set<string>([
    '.pdf', '.txt', '.json', '.xml', '.csv', '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp'
  ]);

  private fileLoadSub?: Rxjs.Subscription;

  private pushSub(s: Rxjs.Subscription) { this.subscriptions.push(s); }

  private logAndFail(where: string, err: any) {
    const msg = this.stringifyError(err);
    this.loggingService.logMessage(3, `Error in ${where} - ${msg}`);
    this.pageLoadError = `Failed to load ${where}: ${msg}`;
  }

  async ngOnInit(): Promise<void> {
    this.pageLoading = true;

    const initSub = this.contextService.onContextLoaded.subscribe(async (ctx) => {
      try {
        this.loggingService.logMessage(0, 'Success response from context service in claims attachments extension.');

        this.facetsServicesUri = ctx['FacetsServicesUri'];
        // this.configureApimAccess(ctx);

        const cfgSub = this.claimAttachmentsService.getConfig(
          ctx['FacetsServicesUri'],
          ctx['Region'],
          { headers: this.buildAuthHeaders(this.authService.token) }
        ).subscribe({
          next: async (configResponse) => {
            // this.configureApimAccess(ctx, configResponse);
            this.loggingService.logMessage(0, 'Success response from config service in claim attachments extension');
            await this.loadPageData();
            this.pageLoading = false;
            this.cdr.detectChanges();
          },
          error: (e) => this.logAndFail('config', e)
        });
        this.pushSub(cfgSub);

        const refreshSub = this.panelEventService.panelEvents.subscribe({
          next: async (event: any) => {
            if (event.mcEventName === 'DeleteMovedLine' && this.claimData['CLCL_ID'] !== null) {
              this.loggingService.logMessage(0, 'Claim Attachments page reloaded');
              this.pageLoading = true;
              await this.loadPageData();
              this.pageLoading = false;
              this.cdr.detectChanges();
            }
          },
          error: (e) => this.logAndFail('reload', e),
        });
        this.pushSub(refreshSub);

      } catch (e) {
        this.logAndFail('initialization', e);
      } finally {
        this.pageLoading = false;
        this.cdr.detectChanges();
      }
    });

    this.pushSub(initSub);
  }

  async loadPageData() {
    try {
      this.claimData = await this.dataIO.getData('CLCL');
      this.syinData = await this.dataIO.getData('$CTXT_SYIN');

      this.atsyData = await this.spInvokeProm(
        'CERSP_ATSY_SEARCH_ATTB_ID',
        { ATTB_ID: 'ATDT' }
      );

      await this.loadAttachmentDataREST();
    } catch (ex) {
      this.logAndFail('data retrieval', ex);
    }
  }

  ngOnDestroy() {
    this.subscriptions.forEach((s) => s.unsubscribe());
    this.fileLoadSub?.unsubscribe();
  }

  private async loadAttachmentDataREST(): Promise<boolean> {
    if (!this.claimData) {
      this.attachmentData = [];
      this.cdr.detectChanges();
      return true;
    }

    const atxr_src = this.claimData.ATXR_SOURCE_ID ?? this.ATXRDefaultId;
    if (atxr_src === this.ATXRDefaultId) {
      this.attachmentData = [];
      this.pageLoadError = null;
      this.cdr.detectChanges();
      return true;
    }

    try {
      const syin_inst = this.syinData['SYIN_INST'];
      const resp = await Rxjs.firstValueFrom(
        this.claimAttachmentsService.getViaExternalService(
          this.facetsServicesUri + `/RestServices/facets/api/v1/attachments/entities/CLCL?ATXR_SOURCE_ID=${atxr_src}&ActiveSyinInst=${syin_inst}`,
          { headers: [{ key: 'Authorization', value: 'Bearer ' + this.authService.token }] }
        )
      );

      const atdt_data = resp['Data']?.['Attachments']?.['ATDT_COLL'] ?? [];
      const atnt_data = resp['Data']?.['Attachments']?.['ATNT_COLL'] ?? [];

      this.attachmentData = this.mapAttachments(atdt_data);
      const noteMap = this.mapNotes(atnt_data);
      this.linkNotes(this.attachmentData, noteMap);
      this.attachmentData = this.sortAttachments(this.attachmentData);
      this.pageLoadError = null;
      this.loggingService.logMessage(0, 'Attachment data loaded');
      this.cdr.detectChanges();
      return true;
    } catch (e) {
      this.logAndFail('Get and map Attachment Data', e);
      return false;
    }
  }

  openFile(att: Interfaces.ClaimAttachment, event?: MouseEvent) {
    event?.preventDefault();
    event?.stopPropagation();

    const prevView = this.view;
    const ext = this.getExt(att.filename);
    const canIframe = this.iframeAllowListSet.has(ext);

    this.view = {
      open: true,
      loading: true,
      error: '',
      canIframe,
      filename: att.filename,
      directory: att.directory,
      iframeBlobUrl: null,
      downloadUrl: null,
      notes: att.notes ?? []
    };

    this.revoke(prevView.iframeBlobUrl);
    this.revoke(prevView.downloadUrl);

    const claimId = this.getCurrentClaimId();
    console.log('[ClaimAttachments] openFile claimData=', JSON.stringify(this.claimData), 'claimId=', claimId);
    const url = this.buildDownloadUrl(this.downloadFileUrl, att.filename, att.directory, claimId);
    const sub = this.claimAttachmentsService.getViaExternalService(url, {
      responseType: 'blob',
      headers: this.buildApimHeaders(this.authService.token, false)
    }).subscribe({
      next: (blob: Blob) => {
        const objectUrl = URL.createObjectURL(blob);
        this.view = {
          ...this.view,
          loading: false,
          error: '',
          iframeBlobUrl: canIframe ? objectUrl : null,
          downloadUrl: canIframe ? null : objectUrl
        };
        if (canIframe && this.viewerIframe?.nativeElement) {
          this.setIFrame(this.view.iframeBlobUrl);
        }
        this.cdr.detectChanges();
      },
      error: (e) => {
        const error = `Unable to load file: ${e.message}`;
        this.loggingService.logMessage(3, `Error: ${error}`);
        this.view = {
          ...this.view,
          loading: false,
          error
        };
        this.cdr.detectChanges();
      }
    });

    this.fileLoadSub?.unsubscribe();
    this.fileLoadSub = sub;
  }

  private setIFrame(blobUrl?: string | null, tries = 0): void {
    const iframe = this.viewerIframe?.nativeElement;
    if (iframe) {
      iframe.src = blobUrl || '';
      return;
    }
    if (tries >= 10) return;
    setTimeout(() => this.setIFrame(blobUrl, tries + 1), 25);
  }

  closeFile() {
    this.revoke(this.view.iframeBlobUrl);
    this.revoke(this.view.downloadUrl);

    this.view = {
      open: false,
      loading: false,
      error: '',
      canIframe: false,
      filename: '',
      directory: '',
      iframeBlobUrl: null,
      downloadUrl: null,
      notes: []
    };

    if (this.viewerIframe?.nativeElement) {
      this.viewerIframe.nativeElement.removeAttribute('src');
    }
  }

  private uploadFile$(file: File, directory: string, ususId: string, claimId: string) {
    if (!file) throw new Error('no file selected');
    if (!directory) throw new Error('atsyId required');
    if (!ususId) throw new Error('USUS_ID required');
    if (!claimId) throw new Error('CLCL_ID required');

    const formData = new FormData();
    formData.append('file', file, file.name);
    formData.append('dir', directory);
    formData.append('ususId', ususId);
    formData.append('claimId', claimId);

    return this.claimAttachmentsService.postViaExternalService(
      this.uploadFileUrl,
      formData,
      { headers: this.buildApimHeaders(this.authService.token, false) }
    );
  }

  private generateAtxr$(atxrSourceId: string, atxrDestId: string): Rxjs.Observable<any> {
    return this.claimAttachmentsService.spInvoke('CERSP_ATTO_SELECT_GEN_IDS', {
      ATXR_SOURCE_ID: atxrSourceId,
      ATSY_ID: this.attachmentAttbId,
      ATXR_DEST_ID: atxrDestId
    });
  }

  private addAtdt$(atxr_src: string, atxr_dest: string, filename: string, atsyId: string) {
    return this.claimAttachmentsService.spInvoke('CERSP_ATDT_APPLY', {
      ATSY_ID: atsyId,
      ATXR_DEST_ID: atxr_dest,
      ATDT_SEQ_NO: 0,
      ATDT_DATA: filename,
      ATDL_ID: atsyId,
      ATXR_SOURCE_ID: atxr_src
    });
  }

  private addAtnt$(atxr_dest: string, atxr_attach: string, atnt_type: string, styleId: string) {
    return this.claimAttachmentsService.spInvoke('CERSP_ATNT_APPLY', {
      ATSY_ID: styleId,
      ATXR_DEST_ID: atxr_dest,
      ATNT_SEQ_NO: 0,
      ATNT_TYPE: atnt_type,
      ATXR_ATTACH_ID: atxr_attach
    });
  }

  private atndSanitize(text: string) {
    let s = (text ?? '').toString();
    s = s.normalize('NFKC');
    s = s.replace(/[\r\n]+/g, ' ');
    return s;
  }

  private addAtnd$(atxr_dest: string, styleId: string, text: string, atndSeqNo: number = 0) {
    return this.claimAttachmentsService.spInvoke('CERSP_ATND_APPLY', {
      ATSY_ID: styleId,
      ATXR_DEST_ID: atxr_dest,
      ATNT_SEQ_NO: 0,
      ATND_SEQ_NO: atndSeqNo,
      ATND_TEXT: this.atndSanitize(text)
    });
  }

  private addAtxr$(atxrSourceId: string, atxrDestId: string, atsyId: string, desc: string, ususId: string) {
    const ts = this.nowLocalISOString();
    return this.claimAttachmentsService.spInvoke('CERSP_ATXR_APPLY', {
      ATXR_SOURCE_ID: atxrSourceId,
      ATXR_DEST_ID: atxrDestId,
      ATSY_ID: atsyId,
      ATTB_ID: 'CLCL',
      ATTB_TYPE: 'S',
      ATXR_DESC: desc,
      ATXR_CREATE_DT: ts,
      ATXR_CREATE_USUS: ususId,
      ATXR_LAST_UPD_DT: ts,
      ATXR_LAST_UPD_USUS: ususId,
      ATXR_COMPILED_KEY: ''
    });
  }

  private updateClclAtxr$(atxrSourceId: string) {
    if (!atxrSourceId) return Rxjs.of(null);
    const new_data = { ...this.claimData, ATXR_SOURCE_ID: atxrSourceId };
    return this.claimAttachmentsService.spInvoke('CMCSP_CLCL_APPLY', new_data);
  }

  private async ensureClclAtxrSourceId(): Promise<string> {
    const cur = this.claimData?.ATXR_SOURCE_ID;
    if (cur && cur !== this.ATXRDefaultId) return cur;

    const gen = await Rxjs.firstValueFrom(this.generateAtxr$(cur ?? this.ATXRDefaultId, this.ATXRDefaultId));
    const src = gen?.['Data']?.['ResultSets']?.[0]?.['Rows']?.[0]?.['COL1'] ?? '';
    if (!src) throw new Error('ensureClclAtxrSourceId: ATXR_SOURCE_ID not returned');

    await Rxjs.firstValueFrom(this.updateClclAtxr$(src));
    this.claimData.ATXR_SOURCE_ID = src;
    return src;
  }

  private async addAtdtData$(atxr_src: string, filename: string, atsyId: string, ususId: string): Promise<string> {
    const gen = await Rxjs.firstValueFrom(this.generateAtxr$(atxr_src, this.ATXRDefaultId));
    const atxr_dest = gen?.['Data']?.['ResultSets']?.[0]?.['Rows']?.[0]?.['COL3'] ?? '';
    if (!atxr_dest) throw new Error('AddAtdt: No ATXR_DEST_ID returned');

    await Promise.all([
      Rxjs.firstValueFrom(this.addAtdt$(atxr_src, atxr_dest, filename, atsyId)),
      Rxjs.firstValueFrom(this.addAtxr$(atxr_src, atxr_dest, atsyId, 'Claim Attachment', ususId))
    ]);

    return atxr_dest;
  }

  private chunkNoteText(src: string, size: number = 100): string[] {
    const s = (src?.trim() ?? '').toString();
    if (!s) return [];

    const out: string[] = [];
    for (let i = 0; i < s.length; i += size) {
      const end = Math.min(i + size, s.length);
      out.push(s.slice(i, end));
    }
    return out;
  }

  private async addNoteData$(atxr_src: string, atxr_attach: string, atnt_type: string, styleId: string, text: string, ususId: string): Promise<string> {
    const gen = await Rxjs.firstValueFrom(this.generateAtxr$(atxr_src, this.ATXRDefaultId));
    const atxr_dest = gen?.['Data']?.['ResultSets']?.[0]?.['Rows']?.[0]?.['COL3'] ?? '';
    if (!atxr_dest) throw new Error('AddAtnd: No ATXR_DEST_ID returned');

    const parts = this.chunkNoteText(text);
    const promiseAll = [
      Rxjs.firstValueFrom(this.addAtnt$(atxr_dest, atxr_attach, atnt_type, styleId)),
      Rxjs.firstValueFrom(this.addAtxr$(atxr_src, atxr_dest, this.noteAtsyId, 'Claim Attachment Note', ususId))
    ];

    for (let i = 0; i < parts.length; i++) {
      promiseAll.push(Rxjs.firstValueFrom(this.addAtnd$(atxr_dest, styleId, parts[i], i)));
    }

    await Promise.all(promiseAll);
    return atxr_dest;
  }

  private buildAttachmentForm(): Interfaces.AttachmentForm {
    const today = new Date();
    const yyyy = today.getFullYear();
    const m = String(today.getMonth() + 1).padStart(2, '0');
    const d = String(today.getDate()).padStart(2, '0');

    return {
      atsyId: null,
      file: null,
      note: '',
      mailToDate: `${yyyy}-${m}-${d}`
    };
  }

  openAttachmentForm() {
    this.hideNote();
    this.attachmentForm = this.buildAttachmentForm();
    this.attachmentFormOpen = true;
    this.attachmentFormSubmitting = false;
    this.attachmentFormError = null;
  }

  closeAttachmentForm() {
    this.attachmentForm = null;
    this.attachmentFormOpen = false;
    this.attachmentFormSubmitting = false;
    this.attachmentFormError = null;
  }

  updateAttachmentForm<K extends keyof Interfaces.AttachmentForm>(key: K, value: Interfaces.AttachmentForm[K]) {
    this.attachmentForm = { ...this.attachmentForm!, [key]: value };
    this.cdr.detectChanges();
  }

  get isAttachmentFormValid(): boolean {
    return !!this.attachmentForm?.atsyId && !!this.attachmentForm?.mailToDate && !!this.attachmentForm?.file;
  }

  onFileSelect(e: Event) {
    const input = e.target as HTMLInputElement;
    if (!input?.files?.length) return;
    if (this.attachmentForm) this.attachmentForm.file = input.files[0];
  }

  async submitAttachmentForm() {
    if (!this.isAttachmentFormValid) return;
    this.loggingService.logMessage(0, 'Upload started.');
    this.attachmentFormSubmitting = true;
    this.attachmentFormError = null;

    try {
      const filename = await this.uploadAttachmentForm();
      this.loggingService.logMessage(0, `Upload complete. Attachment File: ${filename}. Claim: ${this.claimData['CLCL_ID']}`);
      const refreshed = await this.loadAttachmentDataREST();
      if (!refreshed) {
        throw new Error('Upload succeeded but attachment list refresh failed.');
      }

      this.ngZone.run(() => {
        this.attachmentForm = null;
        this.attachmentFormOpen = false;
        this.attachmentFormSubmitting = false;
        this.attachmentFormError = null;
        this.cdr.detectChanges();
      });
    } catch (err: any) {
      this.attachmentFormError = String(err?.message ?? err);
      this.loggingService.logMessage(3, `Error: ${this.attachmentFormError}`);
      this.attachmentFormSubmitting = false;
    }
  }

  private async uploadAttachmentForm(): Promise<string> {
    const atsyId = this.attachmentForm!.atsyId!;
    const file = this.attachmentForm!.file!;
    const ususId = this.syinData?.USUS_ID ?? '';
    const claimId = this.getCurrentClaimId();
    console.log('[ClaimAttachments] uploadAttachmentForm claimData=', JSON.stringify(this.claimData), 'claimId=', claimId);
    const mailToDate = this.attachmentForm!.mailToDate;
    const noteText = (this.attachmentForm!.note || '').trim();

    const upload = await Rxjs.firstValueFrom(this.uploadFile$(file, atsyId, ususId, claimId));
    const storedFilename = upload?.filename ?? upload?.Filename ?? upload?.data?.filename ?? upload?.data?.Filename ?? file.name;

    const atxr_src = await this.ensureClclAtxrSourceId();
    const atxr_dest_atdt = await this.addAtdtData$(atxr_src, storedFilename, atsyId, ususId);

    const date = mailToDate.replace(/^(\d{4})-(\d{2})-(\d{2})$/, '$2/$3/$1');
    const m_atnd_text = `MailToDate for ${storedFilename}: ${date}`;
    await this.addNoteData$(atxr_src, atxr_dest_atdt, this.mailAttnType, this.noteAtsyId, m_atnd_text, ususId);

    if (noteText) {
      await this.addNoteData$(atxr_src, atxr_dest_atdt, '', this.noteAtsyId, noteText, ususId);
    }

    return storedFilename;
  }

  trackById = (_: number, af: any) => af.ATXR_DEST_ID;

  showNoteHover(row: any, el: HTMLElement) {
    if (!row.notes?.length) {
      this.noteHover = { visible: false, top: 0, left: 0, row: null as any, placement: 'bottom' };
      return;
    }
    this.buildNoteHover(row, el);
    this.noteHover.visible = true;
  }

  hideNote() { this.noteHover.visible = false; }
  cancelNoteHide() { this.noteHover.visible = true; }

  private buildNoteHover(row: any, el: HTMLElement) {
    const r = el.getBoundingClientRect();
    const gap = 8, estW = 360, estH = 220;
    const vw = window.innerWidth, vh = window.innerHeight;

    let left = Math.min(Math.max(8, r.left), vw - estW - 8);
    let top = r.bottom;
    let placement: 'bottom' | 'top' = 'bottom';

    if (top + estH > vh) {
      top = Math.max(8, r.top - estH - gap);
      placement = 'top';
    }

    this.noteHover = { visible: true, top, left, row, placement };
  }

  onScrollWrap() { this.hideNote(); }

  openNoteForm(att: Interfaces.ClaimAttachment) {
    this.hideNote();
    this.noteFormOpen = true;
    this.noteFormAttachment = att;
    this.noteFormError = null;
    this.noteFormSubmitting = false;
    this.newNoteText = null;
  }

  closeNoteForm() {
    this.noteFormOpen = false;
    this.noteFormAttachment = null;
    this.noteFormError = null;
    this.noteFormSubmitting = false;
    this.newNoteText = null;
  }

  async submitNoteForm() {
    try {
      this.loggingService.logMessage(0, `Adding note to claim: ${this.claimData['CLCL_ID']}.`);
      this.noteFormSubmitting = true;

      const atxr_src = await this.ensureClclAtxrSourceId();
      await this.addNoteData$(atxr_src, this.noteFormAttachment!.ATXR_DEST_ID, '', this.noteAtsyId, this.newNoteText!, this.syinData['USUS_ID']);
      this.loggingService.logMessage(0, `Added note to claim: ${this.claimData['CLCL_ID']}.`);
      const refreshed = await this.loadAttachmentDataREST();
      if (!refreshed) {
        throw new Error('Note saved but attachment list refresh failed.');
      }

      this.ngZone.run(() => {
        this.noteFormOpen = false;
        this.noteFormAttachment = null;
        this.noteFormError = null;
        this.noteFormSubmitting = false;
        this.newNoteText = null;
        this.cdr.detectChanges();
      });
    } catch (err: any) {
      this.noteFormError = String(err?.message ?? err);
      this.loggingService.logMessage(3, `Error: ${this.noteFormError}`);
      this.noteFormSubmitting = false;
    }
  }

  updateNoteForm(note: string) { this.newNoteText = note; }

  triggerDownload(): void {
    if (!this.view.downloadUrl) return;
    const a = document.createElement('a');
    a.href = this.view.downloadUrl;
    a.download = this.view.filename || 'download';
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  private revoke(url: string | null | undefined): void {
    if (!url) return;
    try { URL.revokeObjectURL(url); } catch {}
  }

  stringifyError(err: any): string {
    if (!err) return 'unknown error';
    if (typeof err === 'string') return err;
    return err.message || JSON.stringify(err);
  }

  buildAuthHeaders(token: string, asJson: boolean = true, contentType: string = ''): { key: string, value: string }[] {
    const headers = [{ key: 'Authorization', value: 'Bearer ' + token }];
    if (contentType) headers.push({ key: 'Content-Type', value: contentType } as any);
    else if (asJson) headers.push({ key: 'Content-Type', value: 'application/json' } as any);
    return headers;
  }

  private buildApimHeaders(token: string, asJson: boolean = true, contentType: string = ''): { key: string, value: string }[] {
    const headers = this.buildAuthHeaders(token, asJson, contentType);
    if (this.apimSubscriptionKey) {
      headers.push({ key: 'Ocp-Apim-Subscription-Key', value: this.apimSubscriptionKey });
    }
    return headers;
  }

  // private configureApimAccess(context: Record<string, any>, configPayload?: any): void {
  //   const baseUrl = this.getSettingValue(context, configPayload, [
  //     'ClaimAttachmentsApiBaseUrl',
  //     'ClaimAttachmentApiBaseUrl',
  //     'AttachmentsApiBaseUrl',
  //     'ApimBaseUrl',
  //     'ApiBaseUrl'
  //   ]);
  //   const downloadUrl = this.getSettingValue(context, configPayload, [
  //     'ClaimAttachmentsDownloadUrl',
  //     'ClaimAttachmentDownloadUrl',
  //     'AttachmentsDownloadUrl',
  //     'DownloadFileUrl',
  //     'ClaimAttachmentsGetFileUrl',
  //     'GetFileUrl'
  //   ]);
  //   const uploadUrl = this.getSettingValue(context, configPayload, [
  //     'ClaimAttachmentsUploadUrl',
  //     'ClaimAttachmentUploadUrl',
  //     'AttachmentsUploadUrl',
  //     'UploadFileUrl'
  //   ]);
  //   const apimSubKey = this.getSettingValue(context, configPayload, [
  //     'ClaimAttachmentsApimSubscriptionKey',
  //     'ClaimAttachmentApimSubscriptionKey',
  //     'ApimSubscriptionKey',
  //     'OcpApimSubscriptionKey',
  //     'SubscriptionKey'
  //   ]);
  //
  //   if (baseUrl) {
  //     const normalizedBaseUrl = baseUrl.replace(/\/+$/, '');
  //     this.downloadFileUrl = `${normalizedBaseUrl}/facets/GetFile`;
  //     this.uploadFileUrl = `${normalizedBaseUrl}/facets/upload`;
  //   }
  //   if (downloadUrl) this.downloadFileUrl = downloadUrl;
  //   if (uploadUrl) this.uploadFileUrl = uploadUrl;
  //   if (apimSubKey) this.apimSubscriptionKey = apimSubKey;
  // }

  // private getSettingValue(context: Record<string, any>, configPayload: any, keys: string[]): string {
  //   for (const key of keys) {
  //     const contextValue = this.findValueByKey(context, key);
  //     const configServiceValue = this.configService.get<string>(key);
  //     const payloadValue = this.findValueByKey(configPayload, key);
  //
  //     const resolvedValue = this.toSettingString(contextValue)
  //       || this.toSettingString(configServiceValue)
  //       || this.toSettingString(payloadValue);
  //     if (resolvedValue) return resolvedValue;
  //   }
  //
  //   return '';
  // }

  // private findValueByKey(source: any, targetKey: string, depth = 0): unknown {
  //   if (!source || typeof source !== 'object' || depth > 6) return undefined;
  //
  //   const normalizedTarget = this.normalizeSettingKey(targetKey);
  //   const entries = Object.entries(source as Record<string, unknown>);
  //   for (const [key, value] of entries) {
  //     if (this.normalizeSettingKey(key) === normalizedTarget) {
  //       return value;
  //     }
  //   }
  //
  //   for (const value of Object.values(source as Record<string, unknown>)) {
  //     if (value && typeof value === 'object') {
  //       const nestedValue = this.findValueByKey(value, targetKey, depth + 1);
  //       if (nestedValue !== undefined) return nestedValue;
  //     }
  //   }
  //
  //   return undefined;
  // }

  // private normalizeSettingKey(value: string): string {
  //   return (value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
  // }

  // private toSettingString(value: unknown): string {
  //   if (typeof value !== 'string') return '';
  //   return value.trim();
  // }

  nowLocalISOString(): string {
    const d = new Date();
    d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
    return d.toISOString().slice(0, 19);
  }

  mapAttachments(data: any): Interfaces.ClaimAttachment[] {
    const attachments: Interfaces.ClaimAttachment[] = [];
    if (!Array.isArray(data)) return attachments;

    const atsyMap = new Map<string, string>(
      this.atsyData.map((a: any) => [a['ATSY_ID'], a['ATSY_DESC']])
    );

    for (const row of data) {
      const attachment: Interfaces.ClaimAttachment = {
        directory: row['ATSY_ID'],
        directoryDesc: atsyMap.get(row['ATSY_ID']) ?? '',
        filename: row['ATDT_DATA'],
        createdOn: row['ATXR_CREATE_DT'],
        createdBy: row['ATXR_CREATE_USUS'],
        updatedOn: row['ATXR_LAST_UPD_DT'],
        updatedBy: row['ATXR_LAST_UPD_USUS'],
        mailToDate: null,
        notes: [],
        ATXR_DEST_ID: row['ATXR_DEST_ID'],
        ATXR_SOURCE_ID: row['ATXR_SOURCE_ID']
      };
      attachments.push(attachment);
    }

    return attachments;
  }

  mapNotes(data: any): Interfaces.Note[] {
    const notes: Interfaces.Note[] = [];
    if (!Array.isArray(data)) return notes;

    for (const row of data) {
      const mailTo = row['ATNT_TYPE'] === 'ATMD';
      let text = row['ALL_ATND_TEXT'] ?? '';
      if (mailTo) {
        const m = text.match(/:\s*(.+)$/);
        text = m ? m[1].trim() : '01/01/0001';
      }
      const note: Interfaces.Note = {
        ATXR_DEST_ID: row['ATXR_DEST_ID'],
        ATXR_SOURCE_ID: row['ATXR_SOURCE_ID'],
        ATXR_ATTACH_ID: row['ATXR_ATTACH_ID'],
        description: row['ATXR_DESC'],
        text,
        ATXR_LAST_UPD_DT: row['ATXR_LAST_UPD_DT'],
        ATXR_LAST_UPD_USUS: row['ATXR_LAST_UPD_USUS'],
        isMailToDate: row['ATNT_TYPE'] === 'ATMD'
      };
      notes.push(note);
    }
    return notes;
  }

  linkNotes(attachments: Interfaces.ClaimAttachment[], notes: Interfaces.Note[]): Interfaces.ClaimAttachment[] {
    const noteMap = new Map<string, Interfaces.Note[]>();
    for (const n of notes) {
      const arr = noteMap.get(n.ATXR_ATTACH_ID);
      if (arr) arr.push(n);
      else noteMap.set(n.ATXR_ATTACH_ID, [n]);
    }

    attachments.forEach(att => {
      const attNotes = (noteMap.get(att.ATXR_DEST_ID) ?? [])
        .sort((a, b) => b.ATXR_LAST_UPD_DT.localeCompare(a.ATXR_LAST_UPD_DT));
      att.notes = attNotes.filter(n => !n.isMailToDate);
      att.mailToDate = attNotes.find(n => n.isMailToDate) ?? null;
    });
    return attachments;
  }

  sortAttachments(attachments: Interfaces.ClaimAttachment[]): Interfaces.ClaimAttachment[] {
    attachments.sort((a, b) => {
      const atime = new Date(a.mailToDate?.text ?? '').getTime() || 0;
      const btime = new Date(b.mailToDate?.text ?? '').getTime() || 0;
      return btime - atime;
    });
    return attachments;
  }

  buildDownloadUrl(downloadUrl: string, filename: string, directory: string, claimId: string = ''): string {
    const qs = new URLSearchParams({ dir: directory, filename: filename });
    if (claimId) qs.set('claimId', claimId);
    let c = '?';
    if (downloadUrl.includes('?')) c = '&';
    return `${downloadUrl}${c}${qs.toString()}`;
  }

  private getCurrentClaimId(): string {
    return (this.claimData?.CLCL_ID ?? '').toString().trim();
  }

  getExt(filename: string): string {
    if (!filename?.includes('.')) return '';
    const ext = filename.split('.').pop()?.toLowerCase();
    return ext ? `.${ext}` : '';
  }

  async spInvokeProm(proc: string, params: Record<string, any>): Promise<any> {
    const resp = await Rxjs.firstValueFrom(this.claimAttachmentsService.spInvoke(proc, params));
    this.loggingService.logMessage(0, `SpInvoke called on '${proc}'`);
    return resp['Data']['ResultSets'][0]['Rows'];
  }
}
