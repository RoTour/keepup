import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';

import { App } from './app';
import { routes } from './app.routes';

describe('App', () => {
  beforeEach(async () => {
    // Given the root shell mounted with the application's real routes
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [provideRouter(routes)],
    }).compileComponents();
  });

  it('should create the app', () => {
    // When the shell is instantiated
    const fixture = TestBed.createComponent(App);

    // Then it exists
    expect(fixture.componentInstance).toBeTruthy();
  });

  it('should render the routed shell', async () => {
    // When the shell renders
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();

    // Then the router outlet host is present
    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.querySelector('[data-testid="app-shell"]')).toBeTruthy();
  });
});
