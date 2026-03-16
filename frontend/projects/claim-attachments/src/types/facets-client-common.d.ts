declare module '@facets-client/common' {
  import { Observable, Subject } from 'rxjs';

  export type HeaderValue = {
    key: string;
    value: string;
  };

  export type RequestOptions = {
    headers?: HeaderValue[] | Record<string, string>;
    responseType?: 'json' | 'blob' | string;
  };

  export class LoggingService {
    LogMessage(level: number, message: string): void;
  }

  export class AuthenticationService {
    token: string;
  }

  export class DataIO {
    getData(id: string, options?: unknown): Promise<any>;
    setData(id: string, value: any): void;
  }

  export class ContextService {
    readonly onContextLoaded: Subject<Record<string, any>>;
    emitContext(context: Record<string, any>): void;
  }

  export class FacetsPanelEventsService {
    readonly panelEvents: Subject<{ mcEventName: string; [key: string]: any }>;
    emitPanelEvent(event: { mcEventName: string; [key: string]: any }): void;
  }

  export class ConfigurationService {
    get<T = unknown>(key: string): T | undefined;
    set(key: string, value: unknown): void;
  }

  export class HttpService {
    getSynchronous<T = any>(url: string): Promise<T>;
    getExternal<T = any>(url: string, options?: RequestOptions): Observable<T>;
    putExternal<T = any>(url: string, data: unknown, options?: RequestOptions): Observable<T>;
    postExternal<T = any>(url: string, data: unknown, options?: RequestOptions): Observable<T>;
    post<T = any>(url: string, body: unknown, options?: RequestOptions): Observable<T>;
  }
}

