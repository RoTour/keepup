// @ts-check
const eslint = require('@eslint/js');
const { defineConfig } = require('eslint/config');
const tseslint = require('typescript-eslint');
const angular = require('angular-eslint');

/**
 * SECURITY: keepup renders LLM-extracted evidence quoted verbatim from
 * learner-submitted text into a trainer's browser. Those strings are
 * attacker-controlled. Every raw-HTML sink is therefore banned outright, as an
 * ERROR, so a violation fails the build rather than printing a warning somebody
 * scrolls past. Render untrusted text through Angular interpolation ({{ ... }}),
 * which escapes. There is no approved escape hatch: if you think you need one,
 * you need a design review, not an eslint-disable.
 */
const HTML_SINK_MESSAGE =
  'Raw-HTML sink is banned: keepup renders attacker-controlled, learner-submitted text. ' +
  'Use Angular interpolation ({{ value }}), which escapes. Do not disable this rule.';

/** Matches innerHTML / outerHTML case-insensitively (Angular also accepts [innerHtml]). */
const HTML_SINK_ATTR = '/^(inner|outer)html$/i';

module.exports = defineConfig([
  {
    files: ['**/*.ts'],
    extends: [
      eslint.configs.recommended,
      tseslint.configs.recommended,
      tseslint.configs.stylistic,
      angular.configs.tsRecommended,
    ],
    processor: angular.processInlineTemplates,
    rules: {
      '@angular-eslint/directive-selector': [
        'error',
        {
          type: 'attribute',
          prefix: 'app',
          style: 'camelCase',
        },
      ],
      '@angular-eslint/component-selector': [
        'error',
        {
          type: 'element',
          prefix: 'app',
          style: 'kebab-case',
        },
      ],

      // SECURITY: raw-HTML sinks reachable from TypeScript.
      'no-restricted-syntax': [
        'error',
        {
          // el.innerHTML = ... / el.outerHTML = ...
          selector: `AssignmentExpression > MemberExpression[property.name=${HTML_SINK_ATTR}]`,
          message: HTML_SINK_MESSAGE,
        },
        {
          // el['innerHTML'] = ...  (computed access would defeat the selector above)
          selector: `AssignmentExpression > MemberExpression[computed=true] > Literal[value=${HTML_SINK_ATTR}]`,
          message: HTML_SINK_MESSAGE,
        },
        {
          // sanitizer.bypassSecurityTrustHtml(...)
          selector: 'CallExpression > MemberExpression[property.name="bypassSecurityTrustHtml"]',
          message: HTML_SINK_MESSAGE,
        },
        {
          // renderer.setProperty(el, 'innerHTML', ...) — the Renderer2 back door.
          selector: `CallExpression[callee.property.name="setProperty"] > Literal[value=${HTML_SINK_ATTR}]`,
          message: HTML_SINK_MESSAGE,
        },
        {
          // el.insertAdjacentHTML(...) / document.write(...)
          selector:
            'CallExpression > MemberExpression[property.name=/^(insertAdjacentHTML|write|writeln)$/]',
          message: HTML_SINK_MESSAGE,
        },
      ],
    },
  },
  {
    // Applies to *.html templates AND to inline templates, which the
    // `angular.processInlineTemplates` processor above extracts into virtual .html files.
    files: ['**/*.html'],
    extends: [angular.configs.templateRecommended, angular.configs.templateAccessibility],
    linterOptions: {
      // SECURITY: templates are where untrusted evidence is actually rendered, so the
      // raw-HTML ban below must not be silenceable. Without this, a single
      // `<!-- eslint-disable-next-line no-restricted-syntax -->` in a template reopens
      // the XSS hole and lint still reports green. Inline ESLint config is therefore
      // switched off for templates; disable directives in .ts files still work normally.
      noInlineConfig: true,
      reportUnusedDisableDirectives: 'error',
    },
    rules: {
      // SECURITY: raw-HTML sinks in templates.
      // [innerHTML]="x", [attr.innerHTML]="x" and bind-innerHTML="x" all parse to
      // BoundAttribute{name:"innerHTML"}; static innerHTML="x" parses to
      // TextAttribute{name:"innerHTML"}. Both shapes are covered.
      'no-restricted-syntax': [
        'error',
        {
          selector: `BoundAttribute[name=${HTML_SINK_ATTR}]`,
          message: HTML_SINK_MESSAGE,
        },
        {
          selector: `TextAttribute[name=${HTML_SINK_ATTR}]`,
          message: HTML_SINK_MESSAGE,
        },
      ],
    },
  },
  {
    // Playwright specs are Node-side test code, not part of the Angular app.
    files: ['e2e/**/*.ts'],
    extends: [eslint.configs.recommended, tseslint.configs.recommended],
    rules: {},
  },
]);
