module.exports = {
  preset: '@react-native/jest-preset',
  roots: ['<rootDir>/packages'],
  testMatch: ['**/__tests__/**/*.test.ts?(x)'],
  modulePathIgnorePatterns: ['<rootDir>/example/', '<rootDir>/packages/.*/lib/'],
  moduleNameMapper: {
    '^react$': '<rootDir>/node_modules/react',
    '^react/(.*)$': '<rootDir>/node_modules/react/$1',
    '^react-native$': '<rootDir>/node_modules/react-native',
    '^react-native/(.*)$': '<rootDir>/node_modules/react-native/$1',
    '^@brudcast/react-native$': '<rootDir>/packages/react-native/src/index',
    '^@brudcast/react-native/module$': '<rootDir>/packages/react-native/src/module',
    '^@brudcast/react-native-in-app$': '<rootDir>/packages/react-native-in-app/src/index',
    '^@brudcast/react-native-push$': '<rootDir>/packages/react-native-push/src/index',
  },
};
