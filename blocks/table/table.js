/* Changed in this project. Derived from https://github.com/adobe/aem-block-collection blocks/table/table.js at 69d7d50839009376687f105cf1e323e05f4ecad2, Apache-2.0. */
/*
 * Table Block
 * Recreate a table
 * https://www.hlx.live/developer/block-collection/table
 */

function buildCell(rowIndex) {
  const cell = rowIndex ? document.createElement('td') : document.createElement('th');
  if (!rowIndex) cell.setAttribute('scope', 'col');
  return cell;
}

export default async function decorate(block) {
  const table = document.createElement('table');
  const thead = document.createElement('thead');
  const tbody = document.createElement('tbody');

  const header = !block.classList.contains('no-header');
  if (header) table.append(thead);
  table.append(tbody);

  [...block.children].forEach((child, i) => {
    const row = document.createElement('tr');
    if (header && i === 0) thead.append(row);
    else tbody.append(row);
    [...child.children].forEach((col) => {
      const cell = buildCell(header ? i : i + 1);
      const align = col.getAttribute('data-align');
      const valign = col.getAttribute('data-valign');
      if (align) cell.style.textAlign = align;
      if (valign) cell.style.verticalAlign = valign;
      cell.innerHTML = col.innerHTML;
      row.append(cell);
    });
  });
  block.innerHTML = '';
  block.append(table);

  // comparison variant: name each mark for assistive tech, so state is not conveyed by colour alone
  if (block.classList.contains('comparison')) {
    const marks = {
      'icon-check-icon-c3bb': 'Supported',
      'icon-check-icon-0824': 'Supported',
      'icon-check-icon-7577': 'Not supported',
    };
    table.querySelectorAll('td span.icon').forEach((icon) => {
      const name = [...icon.classList].find((c) => marks[c]);
      if (!name) return;
      icon.setAttribute('role', 'img');
      icon.setAttribute('aria-label', marks[name]);
    });
  }
}
