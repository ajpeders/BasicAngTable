export interface ClaimAttachment {
  filename: string,
  directory: string,
  directoryDesc: string,
  createdOn: Date,
  createdBy: string,
  updatedOn: Date,
  updatedBy: string,
  mailToDate: Note | null,
  notes: Note[],
  ATXR_DEST_ID: string,
  ATXR_SOURCE_ID: string
}

export interface Note {
  ATXR_DEST_ID: string,
  ATXR_SOURCE_ID: string,
  ATXR_ATTACH_ID: string,
  description: string,
  text: string,
  ATXR_LAST_UPD_DT: string,
  ATXR_LAST_UPD_USUS: string,
  isMailToDate: boolean
}

export interface AttachmentForm {
  atsyId: string | null,
  mailToDate: string,
  file: File | null,
  note: string
}

export interface ViewState {
  open: boolean,
  loading: boolean,
  error: string,
  filename: string,
  canIframe: boolean,
  directory: string,
  iframeBlobUrl: string | null,
  downloadUrl: string | null,
  notes: any[] | null
}

