import { exec } from 'kernelsu-alt';
import { showPrompt, moduleDirectory } from './util.js';
import { getString } from './language.js';
import { FileSelector } from './file_selector.js';

/**
 * Export all Sus'AF config files (and any UserHub scripts) into a
 * tar.gz archive under /storage/emulated/0/Download/.
 * @returns {Promise<void>}
 */
export async function exportConfig() {
    const result = await exec(`sh "${moduleDirectory}/SusAF.sh" --export-config`);
    const output = result.stdout.trim();
    const exportedPath = output.match(/^SUSAF_EXPORT_PATH=(.+)$/m)?.[1];

    if (result.errno === 0 && exportedPath) {
        showPrompt(getString('backup_restore_exported', exportedPath));
    } else if (output.includes('NOTHING_TO_EXPORT')) {
        showPrompt(getString('backup_restore_nothing_to_export'), false);
    } else {
        console.error('Backup failed:', output, result.stderr);
        showPrompt(getString('backup_restore_export_fail'), false);
    }
}

/**
 * Restore config from a tar.gz archive through the module's staged validator.
 * @returns {Promise<void>}
 */
export async function restoreConfig() {
    const path = await FileSelector.getFilePath('tar.gz');
    if (!path) return;
    if (/[\0\r\n]/.test(path)) {
        showPrompt(getString('backup_restore_restore_fail'), false);
        return;
    }
    if (!confirm(getString('backup_restore_confirm'))) return;

    const quotedPath = `'${path.replaceAll("'", `'"'"'`)}'`;
    const result = await exec(`sh "${moduleDirectory}/SusAF.sh" --restore-config ${quotedPath}`);
    if (result.errno === 0) {
        showPrompt(getString('backup_restore_restored'));
    } else {
        console.error('Restore failed:', result.stdout, result.stderr);
        showPrompt(getString('backup_restore_restore_fail'), false);
    }
}
