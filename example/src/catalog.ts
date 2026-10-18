/** A product in the example shop. */
export type Product = {
  id: string;
  name: string;
  price: number;
};

/** The example shop's products. */
export const catalog: readonly Product[] = [
  { id: 'sneakers', name: 'Sneakers', price: 120 },
  { id: 'backpack', name: 'Backpack', price: 80 },
  { id: 'cap', name: 'Cap', price: 25 },
];
