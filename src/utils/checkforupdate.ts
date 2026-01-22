const log = {
    checkforupdate: (msg: string) => console.log(`\x1b[33m[UPDATE CHECK]\x1b[0m ${msg}`)
};

class CheckForUpdate {
    static async checkForUpdate(currentVersion: string): Promise<boolean> {
        try {
            log.checkforupdate('Fetching latest version from GitHub...');
            const response = await fetch('https://raw.githubusercontent.com/cipherfps/ATLAS-Backend/main/package.json');
            
            if (!response.ok) {
                log.checkforupdate(`GitHub fetch failed with status: ${response.status}`);
                log.checkforupdate('This might mean: repository is private, branch name is wrong, or repo doesn\'t exist');
                return false;
            }

            const packageJson = await response.json();
            const latestVersion = packageJson.version;
            
            log.checkforupdate(`GitHub version: ${latestVersion}, Current version: ${currentVersion}`);

            if (isNewerVersion(latestVersion, currentVersion)) {
                log.checkforupdate('Update available!');
                return true;
            }

            log.checkforupdate('Already on latest version');
            return false;
        } catch (error) {
            log.checkforupdate(`Error: ${(error as Error).message}`);
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
