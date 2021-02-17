const accounts = require(`./test-wallets.js`).accounts;

module.exports = {
  mocha: {
    enableTimeouts: false
  },
  providerOptions: {
    default_balance_ether: 100000000000000,
    accounts: accounts
  },
  skipFiles: ['./mocks', './interfaces', './misc'],
  istanbulReporter: ['html', 'json']
};
