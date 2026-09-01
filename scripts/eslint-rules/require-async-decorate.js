/**
 * Require a block's default-exported decorate() to be declared `async`.
 *
 * House rule from AGENTS.md: every block uses one shape, `export default async function
 * decorate(block)`, even when nothing is awaited. airbnb-base has no opinion here — `async` is
 * normally a free choice gated on whether a function awaits — so nothing else catches this.
 *
 * Scope is set by the `overrides` block in .eslintrc.js (blocks/<name>/<name>.js), not by this
 * file: scripts/aem.js is never modified, and an unrelated function named `decorate` elsewhere
 * is not a block entry point.
 */
module.exports = {
  meta: {
    type: 'problem',
    docs: {
      description: 'require a block\'s default-exported decorate() to be async',
    },
    schema: [],
    messages: {
      missingAsync: 'Block decorate() must be declared `async` (AGENTS.md house rule) — add it even when nothing is awaited.',
    },
  },

  create(context) {
    return {
      ExportDefaultDeclaration(node) {
        const fn = node.declaration;
        if (!fn) return;
        if (fn.type !== 'FunctionDeclaration' && fn.type !== 'FunctionExpression') return;
        // A named export that is not the block entry point is none of our business.
        if (fn.id && fn.id.name !== 'decorate') return;
        if (fn.async) return;
        context.report({ node: fn, messageId: 'missingAsync' });
      },
    };
  },
};
