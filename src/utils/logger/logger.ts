import chalk from "chalk";

export default {
  backend(...messages: string[]) {
    console.log(`\x1b[37m[\x1b[96mBACKEND\x1b[0m\x1b[37m]`, ...messages);
  },

  startup(...messages: string[]) {
    console.log(`\x1b[32m[STARTUP]\x1b[0m`, ...messages);
  },

  bot(...messages: string[]) {
    console.log(`\x1b[36m[BOT]\x1b[0m`, ...messages);
  },

  debug(...messages: string[]) {
    // Logging disabled
  },

  error: (...args: unknown[]) => {
    // Logging disabled
  },
};