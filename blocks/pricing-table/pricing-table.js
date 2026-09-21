export default async function decorate(block) {
  [...block.children].forEach((row) => {
    row.classList.add('pricing-table-plan');

    // authored content model: one row per plan, columns in order
    // name, price, feature list, call-to-action link
    const [name, price, features, cta] = [...row.children];

    if (name) name.classList.add('pricing-table-name');
    if (price) price.classList.add('pricing-table-price');
    if (features) features.classList.add('pricing-table-features');
    if (cta) cta.classList.add('pricing-table-cta');
  });
}
