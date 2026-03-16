import * as AngularCore from '@angular/core';
import { HttpService } from '@facets-client/common';
import * as Rxjs from 'rxjs';

@AngularCore.Injectable({
  providedIn: 'root'
})
export class ClaimAttachmentsService {

  constructor(
    private httpService: HttpService
  ) { }

  getViaFacets(url: string): Promise<any> {
    return this.httpService.getSynchronous(url);
  }

  getConfig(serviceUri: string, region: string, options?: any): Rxjs.Observable<any> {
    return this.httpService.getExternal(serviceUri + '/RestServices/facets/api/v1/config/browser/' + region, options)
  }

  getViaExternalService(url: string, options?: any): Rxjs.Observable<any> {
    return this.httpService.getExternal(url, options)
  }

  putViaExternalService(url: string, data: any, options?: any): Rxjs.Observable<any> {
    return this.httpService.putExternal(url, data, options)
  }

  postViaExternalService(url: string, data: any, options?: any): Rxjs.Observable<any> {
    return this.httpService.postExternal(url, data, options)
  }

  spInvoke(proc: string, params: Record<string, any>): Rxjs.Observable<any> {
    return this.httpService.post(
      '/data/procedure/execute',
      this.buildSpInvokeBody(proc, params)
    );
  }

  private buildSpInvokeBody(proc: string, params: Record<string, any>): {} {
    return {
      Analyze: false,
      Identity: 'SVCAGENT',
      Procedure: proc,
      Parameters: params
    };
  }
}
