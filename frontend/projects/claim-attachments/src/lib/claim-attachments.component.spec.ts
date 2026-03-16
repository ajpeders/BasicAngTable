import { ComponentFixture, TestBed } from '@angular/core/testing';
import { HttpClientTestingModule } from '@angular/common/http/testing';
import { Injectable, NgZone } from '@angular/core';
import { Observable, of } from 'rxjs';

import { ClaimAttachmentsComponent } from './claim-attachments.component';
import { ClaimAttachmentsModule } from './claim-attachments.module';
import { ClaimAttachment, Note } from './claim-attachments.interface';
import {
  AuthenticationService,
  ConfigurationService,
  ContextService,
  DataIO,
  FacetsPanelEventsService,
  HttpService,
  LoggingService,
  RequestOptions
} from '@facets-client/common';

// ─── Fake HTTP ───────────────────────────────────────────────────────────────

@Injectable()
class FakeHttpService extends HttpService {
  override getExternal<T = any>(_url: string, options?: RequestOptions): Observable<T> {
    if (options?.responseType === 'blob') {
      return of(new Blob(['content'], { type: 'application/pdf' }) as T);
    }
    return of({
      Data: {
        Attachments: {
          ATDT_COLL: [{
            ATSY_ID: 'ATDT',
            ATDT_DATA: 'test-file.pdf',
            ATXR_CREATE_DT: '2024-01-01T00:00:00',
            ATXR_CREATE_USUS: 'TESTUSER',
            ATXR_LAST_UPD_DT: '2024-01-01T00:00:00',
            ATXR_LAST_UPD_USUS: 'TESTUSER',
            ATXR_DEST_ID: 'ATT-001',
            ATXR_SOURCE_ID: 'SRC-001'
          }],
          ATNT_COLL: [{
            ATNT_TYPE: 'ATMD',
            ALL_ATND_TEXT: 'MailToDate for test-file.pdf: 01/15/2024',
            ATXR_DEST_ID: 'NOTE-001',
            ATXR_SOURCE_ID: 'SRC-001',
            ATXR_ATTACH_ID: 'ATT-001',
            ATXR_DESC: 'Mail To Date',
            ATXR_LAST_UPD_DT: '2024-01-01T00:00:00',
            ATXR_LAST_UPD_USUS: 'TESTUSER'
          }]
        }
      }
    } as T);
  }

  override postExternal<T = any>(_url: string, _data: unknown, _options?: RequestOptions): Observable<T> {
    return of({ filename: 'uploaded-file.pdf' } as T);
  }

  override post<T = any>(_url: string, body: any, _options?: RequestOptions): Observable<T> {
    if (body?.Procedure === 'CERSP_ATTO_SELECT_GEN_IDS') {
      return of({ Data: { ResultSets: [{ Rows: [{ COL1: 'SRC-001', COL3: 'DEST-001' }] }] } } as T);
    }
    return of({ Data: { ResultSets: [{ Rows: [] }] } } as T);
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const makeAttachment = (overrides: Partial<ClaimAttachment> = {}): ClaimAttachment => ({
  filename: 'file.pdf',
  directory: 'ATDT',
  directoryDesc: 'Claim Documents',
  createdOn: new Date('2024-01-01'),
  createdBy: 'USER1',
  updatedOn: new Date('2024-01-01'),
  updatedBy: 'USER1',
  mailToDate: null,
  notes: [],
  ATXR_DEST_ID: 'ATT-001',
  ATXR_SOURCE_ID: 'SRC-001',
  ...overrides
});

const makeNote = (overrides: Partial<Note> = {}): Note => ({
  ATXR_DEST_ID: 'NOTE-001',
  ATXR_SOURCE_ID: 'SRC-001',
  ATXR_ATTACH_ID: 'ATT-001',
  description: 'desc',
  text: 'note text',
  ATXR_LAST_UPD_DT: '2024-01-01T00:00:00',
  ATXR_LAST_UPD_USUS: 'USER1',
  isMailToDate: false,
  ...overrides
});

// ─── Suite ───────────────────────────────────────────────────────────────────

describe('ClaimAttachmentsComponent', () => {
  let component: ClaimAttachmentsComponent;
  let fixture: ComponentFixture<ClaimAttachmentsComponent>;
  let contextService: ContextService;
  let panelEventService: FacetsPanelEventsService;
  let dataIO: DataIO;
  let ngZone: NgZone;

  const seedData = () => {
    dataIO.setData('CLCL', { CLCL_ID: 'CLCL-001', ATXR_SOURCE_ID: 'SRC-001' });
    dataIO.setData('SCTXT_SYIN', { SYIN_INST: '1', USUS_ID: 'TESTUSER' });
  };

  // Emit inside Angular's zone so whenStable() tracks the async work it triggers
  const emitContext = (overrides: Record<string, any> = {}) => {
    ngZone.run(() => {
      contextService.emitContext({
        FacetsServicesUri: 'https://fake.local',
        Region: 'test',
        ...overrides
      });
    });
  };

  const init = async (contextOverrides: Record<string, any> = {}) => {
    fixture.detectChanges();
    seedData();
    emitContext(contextOverrides);
    await fixture.whenStable();
  };

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ClaimAttachmentsModule, HttpClientTestingModule],
      providers: [
        LoggingService,
        AuthenticationService,
        DataIO,
        ContextService,
        FacetsPanelEventsService,
        ConfigurationService,
        { provide: HttpService, useClass: FakeHttpService }
      ]
    }).compileComponents();

    fixture = TestBed.createComponent(ClaimAttachmentsComponent);
    component = fixture.componentInstance;
    contextService = TestBed.inject(ContextService);
    panelEventService = TestBed.inject(FacetsPanelEventsService);
    dataIO = TestBed.inject(DataIO);
    ngZone = TestBed.inject(NgZone);
  });

  // ─── Initialization ────────────────────────────────────────────────────────

  describe('initialization', () => {
    it('should start with pageLoading = true', () => {
      expect(component.pageLoading).toBeTrue();
    });

    it('should set pageLoading = false after context emits', async () => {
      await init();
      expect(component.pageLoading).toBeFalse();
    });

    it('should load attachmentData after context emits', async () => {
      await init();
      expect(component.attachmentData.length).toBe(1);
      expect(component.attachmentData[0].filename).toBe('test-file.pdf');
    });

    it('should link mail-to-date note to attachment', async () => {
      await init();
      expect(component.attachmentData[0].mailToDate).not.toBeNull();
      expect(component.attachmentData[0].mailToDate!.text).toBe('01/15/2024');
    });

    it('should set pageLoadError on initialization failure', async () => {
      fixture.detectChanges();
      spyOn(dataIO, 'getData').and.rejectWith(new Error('data fetch failed'));
      emitContext();
      await fixture.whenStable();
      expect(component.pageLoadError).not.toBeNull();
    });

    it('should build APIM file urls from context base url', async () => {
      await init({ ClaimAttachmentsApiBaseUrl: 'https://apim.test.local/' });
      expect((component as any).downloadFileUrl).toBe('https://apim.test.local/facets/GetFile');
      expect((component as any).uploadFileUrl).toBe('https://apim.test.local/facets/upload');
    });
  });

  // ─── Panel Events ──────────────────────────────────────────────────────────

  describe('panel events', () => {
    it('should reload data on DeleteMovedLine event', async () => {
      await init();
      const spy = spyOn(component, 'loadPageData').and.callThrough();
      panelEventService.emitPanelEvent({ mcEventName: 'DeleteMovedLine' });
      await fixture.whenStable();
      expect(spy).toHaveBeenCalled();
    });

    it('should not reload data for unrelated events', async () => {
      await init();
      const spy = spyOn(component, 'loadPageData').and.callThrough();
      panelEventService.emitPanelEvent({ mcEventName: 'SomeOtherEvent' });
      await fixture.whenStable();
      expect(spy).not.toHaveBeenCalled();
    });

    it('should set pageLoading = false after reload even if loadPageData throws', async () => {
      await init();
      spyOn(component, 'loadPageData').and.rejectWith(new Error('fail'));
      panelEventService.emitPanelEvent({ mcEventName: 'DeleteMovedLine' });
      await fixture.whenStable();
      expect(component.pageLoading).toBeFalse();
    });
  });

  // ─── openFile / closeFile ──────────────────────────────────────────────────

  describe('openFile', () => {
    it('should set view.open = true when called', () => {
      component.openFile(makeAttachment());
      expect(component.view.open).toBeTrue();
    });

    it('should set view.filename and view.directory', () => {
      component.openFile(makeAttachment({ filename: 'report.pdf', directory: 'ATDT' }));
      expect(component.view.filename).toBe('report.pdf');
      expect(component.view.directory).toBe('ATDT');
    });

    it('should set canIframe = true for pdf', () => {
      component.openFile(makeAttachment({ filename: 'test.pdf' }));
      expect(component.view.canIframe).toBeTrue();
    });

    it('should set canIframe = false for unsupported file types', () => {
      component.openFile(makeAttachment({ filename: 'report.docx' }));
      expect(component.view.canIframe).toBeFalse();
    });

    it('should set view.loading = false after blob loads', async () => {
      component.openFile(makeAttachment());
      await fixture.whenStable();
      expect(component.view.loading).toBeFalse();
    });

    it('should set view.error on load failure', async () => {
      const fakeHttp = TestBed.inject(HttpService) as FakeHttpService;
      spyOn(fakeHttp, 'getExternal').and.returnValue(
        new Observable(obs => obs.error({ message: 'network error' }))
      );
      component.openFile(makeAttachment());
      await fixture.whenStable();
      expect(component.view.error).toContain('network error');
    });

    it('should include APIM subscription header when configured', async () => {
      await init({
        ClaimAttachmentsApiBaseUrl: 'https://apim.test.local',
        ClaimAttachmentsApimSubscriptionKey: 'sub-key-123'
      });

      const fakeHttp = TestBed.inject(HttpService) as FakeHttpService;
      const spy = spyOn(fakeHttp, 'getExternal').and.callThrough();

      component.openFile(makeAttachment());
      await fixture.whenStable();

      const options = spy.calls.mostRecent().args[1] as RequestOptions;
      const headers = options.headers as Array<{ key: string; value: string }>;
      expect(headers.some(h => h.key === 'Authorization')).toBeTrue();
      expect(headers.some(h => h.key === 'Ocp-Apim-Subscription-Key' && h.value === 'sub-key-123')).toBeTrue();
    });
  });

  describe('closeFile', () => {
    it('should reset view to closed state', async () => {
      component.openFile(makeAttachment());
      await fixture.whenStable();
      component.closeFile();
      expect(component.view.open).toBeFalse();
      expect(component.view.filename).toBe('');
      expect(component.view.iframeBlobUrl).toBeNull();
    });
  });

  // ─── Attachment Form ───────────────────────────────────────────────────────

  describe('attachment form', () => {
    it('should open form with a fresh AttachmentForm', () => {
      component.openAttachmentForm();
      expect(component.attachmentFormOpen).toBeTrue();
      expect(component.attachmentForm).not.toBeNull();
      expect(component.attachmentForm!.atsyId).toBeNull();
      expect(component.attachmentForm!.file).toBeNull();
    });

    it('should close form and clear state', () => {
      component.openAttachmentForm();
      component.closeAttachmentForm();
      expect(component.attachmentFormOpen).toBeFalse();
      expect(component.attachmentForm).toBeNull();
      expect(component.attachmentFormError).toBeNull();
    });

    it('isAttachmentFormValid should be false when form is empty', () => {
      component.openAttachmentForm();
      expect(component.isAttachmentFormValid).toBeFalse();
    });

    it('isAttachmentFormValid should be true with atsyId, file, and date', () => {
      component.openAttachmentForm();
      component.updateAttachmentForm('atsyId', 'ATDT');
      component.updateAttachmentForm('file', new File(['content'], 'test.pdf'));
      expect(component.isAttachmentFormValid).toBeTrue();
    });

    it('should not submit when form is invalid', async () => {
      await init();
      component.openAttachmentForm();
      const spy = spyOn(component as any, 'uploadAttachmentForm');
      await component.submitAttachmentForm();
      expect(spy).not.toHaveBeenCalled();
    });

    it('should close form after successful submit', async () => {
      await init();
      component.openAttachmentForm();
      component.updateAttachmentForm('atsyId', 'ATDT');
      component.updateAttachmentForm('file', new File(['content'], 'test.pdf'));
      await component.submitAttachmentForm();
      await fixture.whenStable();
      expect(component.attachmentFormOpen).toBeFalse();
    });

    it('should include APIM subscription header on upload when configured', async () => {
      await init({
        ClaimAttachmentsApiBaseUrl: 'https://apim.test.local',
        ClaimAttachmentsApimSubscriptionKey: 'sub-key-abc'
      });

      const fakeHttp = TestBed.inject(HttpService) as FakeHttpService;
      const spy = spyOn(fakeHttp, 'postExternal').and.callThrough();

      component.openAttachmentForm();
      component.updateAttachmentForm('atsyId', 'ATDT');
      component.updateAttachmentForm('file', new File(['content'], 'test.pdf'));
      await component.submitAttachmentForm();
      await fixture.whenStable();

      const options = spy.calls.mostRecent().args[2] as RequestOptions;
      const headers = options.headers as Array<{ key: string; value: string }>;
      expect(headers.some(h => h.key === 'Authorization')).toBeTrue();
      expect(headers.some(h => h.key === 'Ocp-Apim-Subscription-Key' && h.value === 'sub-key-abc')).toBeTrue();
    });
  });

  // ─── Note Form ─────────────────────────────────────────────────────────────

  describe('note form', () => {
    it('should open note form with the target attachment', async () => {
      await init();
      const att = component.attachmentData[0];
      component.openNoteForm(att);
      expect(component.noteFormOpen).toBeTrue();
      expect(component.noteFormAttachment).toBe(att);
    });

    it('should close note form and reset state', async () => {
      await init();
      component.openNoteForm(component.attachmentData[0]);
      component.closeNoteForm();
      expect(component.noteFormOpen).toBeFalse();
      expect(component.noteFormAttachment).toBeNull();
      expect(component.newNoteText).toBeNull();
    });

    it('should close form after successful note submit', async () => {
      await init();
      component.openNoteForm(component.attachmentData[0]);
      component.updateNoteForm('some note text');
      await component.submitNoteForm();
      await fixture.whenStable();
      expect(component.noteFormOpen).toBeFalse();
    });
  });

  // ─── Note Hover ────────────────────────────────────────────────────────────

  describe('note hover', () => {
    it('should not show hover when attachment has no notes', () => {
      const att = makeAttachment({ notes: [] });
      component.showNoteHover(att, document.createElement('div'));
      expect(component.noteHover.visible).toBeFalse();
    });

    it('should show hover when attachment has notes', () => {
      const att = makeAttachment({ notes: [makeNote()] });
      const el = document.createElement('div');
      spyOn(el, 'getBoundingClientRect').and.returnValue(
        { top: 100, bottom: 120, left: 50, right: 200, width: 150, height: 20 } as DOMRect
      );
      component.showNoteHover(att, el);
      expect(component.noteHover.visible).toBeTrue();
      expect(component.noteHover.row).toBe(att);
    });

    it('hideNote should set visible = false', () => {
      component.noteHover.visible = true;
      component.hideNote();
      expect(component.noteHover.visible).toBeFalse();
    });

    it('cancelNoteHide should restore visible = true', () => {
      component.noteHover.visible = false;
      component.cancelNoteHide();
      expect(component.noteHover.visible).toBeTrue();
    });
  });

  // ─── mapAttachments ────────────────────────────────────────────────────────

  describe('mapAttachments', () => {
    it('should return empty array for non-array input', () => {
      expect(component.mapAttachments(null)).toEqual([]);
      expect(component.mapAttachments({})).toEqual([]);
    });

    it('should map row fields to ClaimAttachment', () => {
      const row = {
        ATSY_ID: 'ATDT',
        ATDT_DATA: 'file.pdf',
        ATXR_CREATE_DT: '2024-01-01',
        ATXR_CREATE_USUS: 'USER1',
        ATXR_LAST_UPD_DT: '2024-01-02',
        ATXR_LAST_UPD_USUS: 'USER2',
        ATXR_DEST_ID: 'DEST-001',
        ATXR_SOURCE_ID: 'SRC-001'
      };
      const result = component.mapAttachments([row]);
      expect(result.length).toBe(1);
      expect(result[0].filename).toBe('file.pdf');
      expect(result[0].directory).toBe('ATDT');
      expect(result[0].ATXR_DEST_ID).toBe('DEST-001');
      expect(result[0].notes).toEqual([]);
      expect(result[0].mailToDate).toBeNull();
    });
  });

  // ─── mapNotes ──────────────────────────────────────────────────────────────

  describe('mapNotes', () => {
    it('should return empty array for non-array input', () => {
      expect(component.mapNotes(null)).toEqual([]);
    });

    it('should extract date from ATMD note text', () => {
      const row = {
        ATNT_TYPE: 'ATMD',
        ALL_ATND_TEXT: 'MailToDate for file.pdf: 03/15/2024',
        ATXR_DEST_ID: 'NOTE-001', ATXR_SOURCE_ID: 'SRC-001',
        ATXR_ATTACH_ID: 'ATT-001', ATXR_DESC: 'desc',
        ATXR_LAST_UPD_DT: '2024-01-01', ATXR_LAST_UPD_USUS: 'USER1'
      };
      const result = component.mapNotes([row]);
      expect(result[0].isMailToDate).toBeTrue();
      expect(result[0].text).toBe('03/15/2024');
    });

    it('should keep full text for non-ATMD notes', () => {
      const row = {
        ATNT_TYPE: '', ALL_ATND_TEXT: 'A regular note.',
        ATXR_DEST_ID: 'NOTE-002', ATXR_SOURCE_ID: 'SRC-001',
        ATXR_ATTACH_ID: 'ATT-001', ATXR_DESC: 'desc',
        ATXR_LAST_UPD_DT: '2024-01-01', ATXR_LAST_UPD_USUS: 'USER1'
      };
      const result = component.mapNotes([row]);
      expect(result[0].isMailToDate).toBeFalse();
      expect(result[0].text).toBe('A regular note.');
    });

    it('should default ATMD text to 01/01/0001 when pattern does not match', () => {
      const row = {
        ATNT_TYPE: 'ATMD', ALL_ATND_TEXT: 'no colon here',
        ATXR_DEST_ID: 'NOTE-003', ATXR_SOURCE_ID: 'SRC-001',
        ATXR_ATTACH_ID: 'ATT-001', ATXR_DESC: 'desc',
        ATXR_LAST_UPD_DT: '2024-01-01', ATXR_LAST_UPD_USUS: 'USER1'
      };
      const result = component.mapNotes([row]);
      expect(result[0].text).toBe('01/01/0001');
    });
  });

  // ─── linkNotes ─────────────────────────────────────────────────────────────

  describe('linkNotes', () => {
    it('should link notes to matching attachment', () => {
      const att = makeAttachment();
      const note = makeNote();
      component.linkNotes([att], [note]);
      expect(att.notes.length).toBe(1);
      expect(att.notes[0].text).toBe('note text');
    });

    it('should separate mailToDate note from regular notes', () => {
      const att = makeAttachment();
      const mailNote = makeNote({ isMailToDate: true, text: '03/15/2024' });
      component.linkNotes([att], [mailNote]);
      expect(att.notes.length).toBe(0);
      expect(att.mailToDate).not.toBeNull();
      expect(att.mailToDate!.text).toBe('03/15/2024');
    });

    it('should not link notes to non-matching attachments', () => {
      const att = makeAttachment({ ATXR_DEST_ID: 'ATT-999' });
      const note = makeNote({ ATXR_ATTACH_ID: 'ATT-001' });
      component.linkNotes([att], [note]);
      expect(att.notes.length).toBe(0);
    });
  });

  // ─── sortAttachments ───────────────────────────────────────────────────────

  describe('sortAttachments', () => {
    it('should sort by mailToDate descending', () => {
      const att1 = makeAttachment({ filename: 'a.pdf', ATXR_DEST_ID: 'ATT-001', mailToDate: makeNote({ text: '01/01/2024', isMailToDate: true }) });
      const att2 = makeAttachment({ filename: 'b.pdf', ATXR_DEST_ID: 'ATT-002', mailToDate: makeNote({ text: '03/01/2024', isMailToDate: true }) });
      const result = component.sortAttachments([att1, att2]);
      expect(result[0].filename).toBe('b.pdf');
      expect(result[1].filename).toBe('a.pdf');
    });

    it('should place attachments without mailToDate at the end', () => {
      const att1 = makeAttachment({ filename: 'no-date.pdf', ATXR_DEST_ID: 'ATT-001', mailToDate: null });
      const att2 = makeAttachment({ filename: 'has-date.pdf', ATXR_DEST_ID: 'ATT-002', mailToDate: makeNote({ text: '01/01/2024', isMailToDate: true }) });
      const result = component.sortAttachments([att1, att2]);
      expect(result[0].filename).toBe('has-date.pdf');
      expect(result[1].filename).toBe('no-date.pdf');
    });
  });

  // ─── buildDownloadUrl ──────────────────────────────────────────────────────

  describe('buildDownloadUrl', () => {
    it('should append ? when no existing query string', () => {
      const url = component.buildDownloadUrl('https://example.com/dl', 'file.pdf', 'ATDT');
      expect(url).toContain('?');
      expect(url).toContain('filename=file.pdf');
      expect(url).toContain('dir=ATDT');
    });

    it('should append & when query string already present', () => {
      const url = component.buildDownloadUrl('https://example.com/dl?token=abc', 'file.pdf', 'ATDT');
      expect(url).toContain('&');
      expect(url).not.toMatch(/\?.*\?/);
    });
  });

  // ─── getExt ────────────────────────────────────────────────────────────────

  describe('getExt', () => {
    it('should return extension with leading dot', () => {
      expect(component.getExt('file.pdf')).toBe('.pdf');
    });

    it('should return last extension for multi-dot filenames', () => {
      expect(component.getExt('archive.tar.gz')).toBe('.gz');
    });

    it('should return lowercase extension', () => {
      expect(component.getExt('FILE.PDF')).toBe('.pdf');
    });

    it('should return empty string for no extension', () => {
      expect(component.getExt('filename')).toBe('');
    });
  });

  // ─── stringifyError ────────────────────────────────────────────────────────

  describe('stringifyError', () => {
    it('should return "unknown error" for null/undefined', () => {
      expect(component.stringifyError(null)).toBe('unknown error');
      expect(component.stringifyError(undefined)).toBe('unknown error');
    });

    it('should return the string directly', () => {
      expect(component.stringifyError('some error')).toBe('some error');
    });

    it('should return message from Error object', () => {
      expect(component.stringifyError(new Error('test error'))).toBe('test error');
    });
  });

  // ─── nowLocalISOString ─────────────────────────────────────────────────────

  describe('nowLocalISOString', () => {
    it('should return datetime in yyyy-mm-ddThh:mm:ss format', () => {
      expect(component.nowLocalISOString()).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/);
    });
  });

  // ─── buildAuthHeaders ──────────────────────────────────────────────────────

  describe('buildAuthHeaders', () => {
    it('should include Authorization header', () => {
      const headers = component.buildAuthHeaders('my-token');
      expect(headers.some(h => h.key === 'Authorization' && h.value === 'Bearer my-token')).toBeTrue();
    });

    it('should include application/json Content-Type by default', () => {
      const headers = component.buildAuthHeaders('my-token');
      expect(headers.some(h => h.key === 'Content-Type' && h.value === 'application/json')).toBeTrue();
    });

    it('should omit Content-Type when asJson is false', () => {
      const headers = component.buildAuthHeaders('my-token', false);
      expect(headers.some(h => h.key === 'Content-Type')).toBeFalse();
    });

    it('should use custom contentType when provided', () => {
      const headers = component.buildAuthHeaders('my-token', true, 'text/plain');
      expect(headers.some(h => h.key === 'Content-Type' && h.value === 'text/plain')).toBeTrue();
    });
  });
});
