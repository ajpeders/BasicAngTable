import * as AngularCommon from '@angular/common';
import * as AngularHttp from '@angular/common/http';
import { NgModule } from '@angular/core';

import { ClaimAttachmentsComponent } from './claim-attachments.component';

@NgModule({
  declarations: [
    ClaimAttachmentsComponent
  ],
  imports: [
    AngularCommon.CommonModule,
    AngularHttp.HttpClientModule
  ],
  exports: [
    ClaimAttachmentsComponent
  ]
})
export class ClaimAttachmentsModule { }
