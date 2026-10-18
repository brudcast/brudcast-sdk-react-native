declare module 'brudcast-example-config' {
  const settings: {
    publishableKey?: string;
    environment?: string;
    localPort?: number;
    sampleBackendUrl?: string;
  };
  export default settings;
}
