'use strict';

/**
 * @typedef {import("markdownlint").Options & { globs?: string[], ignores: string[]}} Options
 */

/** @type {Options} */
const config = {
  config: {
    extends: require.resolve('markdownlint/style/prettier'),
    'list-marker-space': {
      ul_multi: 1,
      ul_single: 1,
    },
    'ul-indent': {
      indent: 2,
    },

    // Disable some built-in rules
    'first-line-heading': false,
    'line-length': false,
    'no-emphasis-as-header': false,
    'no-inline-html': false,
    'single-h1': false,
  },

  // Define glob expressions to use (only valid at root)
  // globs: ['**/*.md'],

  // Define glob expressions to ignore
  ignores: ['.yarn', '.pnpm-store', '**/node_modules/**', '**/TestResults/**', '**/bin/**', '**/obj/**', 'coverage/', 'terra/.terraform/**'],
};

module.exports = config;
