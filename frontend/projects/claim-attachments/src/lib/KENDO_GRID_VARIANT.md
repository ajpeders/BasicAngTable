# Kendo Grid Variant (Optional)

This library keeps the current native table as the default implementation.

An alternate template with a Kendo grid is available at:

- `projects/claim-attachments/src/lib/claim-attachments.kendo-grid.view.html`

## Enable the Kendo variant

1. Ensure Kendo Angular Grid packages are available in the build environment (the same one that builds your parent app).

2. Import `GridModule` in:
- `projects/claim-attachments/src/lib/claim-attachments.module.ts`

Example:

```ts
import { GridModule } from '@progress/kendo-angular-grid';

@NgModule({
  imports: [
    AngularCommon.CommonModule,
    AngularHttp.HttpClientModule,
    GridModule
  ]
})
```

3. Switch the component template in:
- `projects/claim-attachments/src/lib/claim-attachments.component.ts`

From:

```ts
templateUrl: './claim-attachments.view.html'
```

To:

```ts
templateUrl: './claim-attachments.kendo-grid.view.html'
```

## Revert

Switch `templateUrl` back to `./claim-attachments.view.html`.
