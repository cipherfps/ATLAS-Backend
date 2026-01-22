const log = {
    checkforupdate: (msg: string) => console.log(`\x1b[33m[UPDATE CHECK]\x1b[0m ${msg}`)
};

class CheckForUpdate {
    static async checkForUpdate(currentVersion: string): Promise<boolean> {
        try {
            const response = await fetch('https://raw.githubusercontent.com/Project-Nocturno/ATLAS-Backend/main/package.json');
            if (!response.ok) {
                return false;
            }

            const packageJson = await response.json();
            const latestVersion = packageJson.version;

            if (isNewerVersion(latestVersion, currentVersion)) {
                return true;
            }

            return false;
        } catch (error) {
            return false;
        }
    }
}

function isNewerVersion(latest: string, current: string): boolean {
    const latestParts = latest.split('.').map(Number);
    const currentParts = current.split('.').map(Number);

    for (let i = 0; i < latestParts.length; i++) {
        if (latestParts[i] > (currentParts[i] || 0)) {
            return true;
        } else if (latestParts[i] < (currentParts[i] || 0)) {
            return false;
        }
    }

    return false;
}

export default CheckForUpdate;
