import { useEffect, useState } from 'react';
import { Brudcast } from '@brudcast/react-native';
import { BrudcastInApp } from '@brudcast/react-native-in-app';

import { catalog, type Product } from '../catalog';
import { useNavigation } from '../navigation';
import { Body, Button, Screen } from '../ui';

/**
 * The shop's product list.
 *
 * @returns The screen.
 */
export function ShopScreen() {
  const navigation = useNavigation();
  return (
    <Screen title="Shop">
      {catalog.map((product) => (
        <Button
          key={product.id}
          kind="outlined"
          title={`${product.name}, $${product.price}`}
          onPress={() => navigation.push({ name: 'Product', product })}
          testID={`product-${product.id}`}
        />
      ))}
    </Screen>
  );
}

/**
 * A product, tracked as `product_viewed`.
 *
 * @param props The product.
 * @returns The screen.
 */
export function ProductScreen(props: { product: Product }) {
  const navigation = useNavigation();
  const { product } = props;

  useEffect(() => {
    void Brudcast.track('product_viewed', {
      product: product.id,
      price: product.price,
    });
  }, [product]);

  return (
    <Screen title={product.name}>
      <Body heading>${product.price}</Body>
      <Button
        title="Buy now"
        onPress={() => {
          void Brudcast.track('checkout_started', {
            product: product.id,
            total: product.price,
          });
          navigation.push({ name: 'Checkout' });
        }}
        testID="buy"
      />
    </Screen>
  );
}

/**
 * Checkout. In-app messages are held while it is open, the way an app keeps them out of a payment
 * flow, and `order_completed` is tracked on paying.
 *
 * @returns The screen.
 */
export function CheckoutScreen() {
  const navigation = useNavigation();
  const [paid, setPaid] = useState(false);

  useEffect(() => {
    void BrudcastInApp.pauseDisplay();
    return () => {
      void BrudcastInApp.resumeDisplay();
    };
  }, []);

  return (
    <Screen title="Checkout">
      <Body muted>In-app messages wait until you leave checkout.</Body>
      {paid ? (
        <>
          <Body>Thanks for your order.</Body>
          <Button
            kind="outlined"
            title="Back to home"
            onPress={() => navigation.reset({ name: 'Home' })}
          />
        </>
      ) : (
        <Button
          title="Pay"
          onPress={() => {
            void Brudcast.track('order_completed', { total: 120 });
            setPaid(true);
          }}
          testID="pay"
        />
      )}
    </Screen>
  );
}
