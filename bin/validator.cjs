const { GlobalConfig } = require('/usr/local/renovate/dist/config/global');
const { setPlatformApi } = require('/usr/local/renovate/dist/modules/platform');

// set required global config
GlobalConfig.set({
  platform: 'gitea',
  endpoint: process.env.RENOVATE_ENDPOINT,
});

// set platform api
setPlatformApi('gitea');

// run config validator
require('/usr/local/renovate/dist/config-validator.js');
