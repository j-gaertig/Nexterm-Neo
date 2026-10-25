import { downloadRequest } from "@/common/utils/RequestUtil.js";
import { MAX_GRAPHICS_IMAGE_BYTES } from "@/common/utils/terminalGraphics.js";

const FETCH_TIMEOUT_MS = 15000;

/**
 * Build the fetch callback used by the Kitty `t=f` resolver.
 *
 * `path` is a path on the remote host, *not* a local/browser path. It is read
 * through the authenticated SFTP API so permissions, auditing, and the
 * existing SSH connection behave exactly like the file manager. Returning
 * `null` means "leave the sequence dropped"; errors are handled by the
 * resolver so a missing avatar can never break the rest of the terminal.
 */
export const createRemoteImageFetcher = ({ sessionToken, sessionId, isShared = false } = {}) => {
    if (!sessionToken || !sessionId || isShared) return null;

    return async (path) => {
        const params = new URLSearchParams({
            sessionToken,
            sessionId,
            path,
            preview: "true",
            graphics: "true",
            maxSize: String(MAX_GRAPHICS_IMAGE_BYTES),
        });

        let timer;
        const timeout = new Promise((_, reject) => {
            timer = setTimeout(() => reject(new Error("Timed out while fetching remote terminal image")), FETCH_TIMEOUT_MS);
        });

        try {
            const blob = await Promise.race([
                downloadRequest(`/api/entries/sftp?${params.toString()}`),
                timeout,
            ]);
            if (!blob || blob.size === 0) return null;
            if (blob.size > MAX_GRAPHICS_IMAGE_BYTES) {
                throw new Error("Remote terminal image exceeds the size limit");
            }
            return new Uint8Array(await blob.arrayBuffer());
        } finally {
            clearTimeout(timer);
        }
    };
};
