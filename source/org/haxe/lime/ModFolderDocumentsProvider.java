package org.haxe.lime;

import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.os.CancellationSignal;
import android.os.Environment;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract.Document;
import android.provider.DocumentsContract.Root;
import android.provider.DocumentsProvider;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.Collections;
import java.util.LinkedList;

/**
 * Exposes the external mod folder (/.ImpostorLegacy/) as a quick-access
 * location in Android's Files app — identical to FunkinCrew/Funkin's
 * "Data Folder" shortcut in their DocumentsProvider.
 *
 * Package is com.motorfrog.impostor; authority is
 * com.motorfrog.impostor.documents (declared in AndroidManifest).
 */
public class ModFolderDocumentsProvider extends DocumentsProvider {

    private static final String AUTHORITY = "com.motorfrog.impostor.documents";

    private static final String[] DEFAULT_ROOT_PROJECTION = new String[] {
        Root.COLUMN_ROOT_ID,
        Root.COLUMN_MIME_TYPES,
        Root.COLUMN_FLAGS,
        Root.COLUMN_ICON,
        Root.COLUMN_TITLE,
        Root.COLUMN_SUMMARY,
        Root.COLUMN_DOCUMENT_ID,
        Root.COLUMN_AVAILABLE_BYTES,
    };

    private static final String[] DEFAULT_DOCUMENT_PROJECTION = new String[] {
        Document.COLUMN_DOCUMENT_ID,
        Document.COLUMN_MIME_TYPE,
        Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_LAST_MODIFIED,
        Document.COLUMN_FLAGS,
        Document.COLUMN_SIZE,
    };

    private static File modFolder;
    private static String modFolderPath;

    private static final int MAX_SEARCH_RESULTS = 50;

    @Override
    public boolean onCreate() {
        modFolder = new File(Environment.getExternalStorageDirectory(), ".ImpostorLegacy");
        if (!modFolder.exists()) modFolder.mkdirs();
        try {
            modFolderPath = modFolder.getCanonicalPath();
        } catch (IOException e) {
            modFolderPath = modFolder.getAbsolutePath();
        }
        return true;
    }

    @Override
    public Cursor queryRoots(String[] projection) {
        final MatrixCursor result = new MatrixCursor(
            projection != null ? projection : DEFAULT_ROOT_PROJECTION
        );
        if (modFolder == null) return result;

        final MatrixCursor.RowBuilder row = result.newRow();
        row.add(Root.COLUMN_ROOT_ID,    modFolderPath);
        row.add(Root.COLUMN_DOCUMENT_ID, modFolderPath);
        row.add(Root.COLUMN_TITLE,      "VS Impostor Legacy");
        row.add(Root.COLUMN_SUMMARY,    "Mod Folder");
        row.add(Root.COLUMN_ICON,       getContext().getApplicationInfo().icon);
        row.add(Root.COLUMN_FLAGS,
            Root.FLAG_SUPPORTS_CREATE |
            Root.FLAG_SUPPORTS_SEARCH |
            Root.FLAG_SUPPORTS_IS_CHILD |
            Root.FLAG_LOCAL_ONLY);
        row.add(Root.COLUMN_MIME_TYPES,      "*/*");
        row.add(Root.COLUMN_AVAILABLE_BYTES, modFolder.getFreeSpace());
        return result;
    }

    @Override
    public Cursor queryDocument(String documentId, String[] projection) throws FileNotFoundException {
        final MatrixCursor result = new MatrixCursor(
            projection != null ? projection : DEFAULT_DOCUMENT_PROJECTION
        );
        includeFile(result, documentId, null);
        return result;
    }

    @Override
    public Cursor queryChildDocuments(String parentDocumentId, String[] projection, String sortOrder)
            throws FileNotFoundException {
        final MatrixCursor result = new MatrixCursor(
            projection != null ? projection : DEFAULT_DOCUMENT_PROJECTION
        );
        final File parent = getFileForDocId(parentDocumentId);
        File[] children = null;
        try {
            children = parent.listFiles();
        } catch (SecurityException e) {
            children = new File[0];
        }
        if (children != null) {
            for (File child : children)
                includeFile(result, null, child);
        }
        return result;
    }

    @Override
    public Cursor querySearchDocuments(String rootId, String query, String[] projection)
            throws FileNotFoundException {
        final MatrixCursor result = new MatrixCursor(
            projection != null ? projection : DEFAULT_DOCUMENT_PROJECTION
        );
        final LinkedList<File> pending = new LinkedList<>();
        pending.add(getFileForDocId(rootId));

        while (!pending.isEmpty() && result.getCount() < MAX_SEARCH_RESULTS) {
            final File file = pending.removeFirst();

            boolean isInsideRoot;
            try {
                isInsideRoot = file.getCanonicalPath().startsWith(modFolderPath);
            } catch (IOException e) {
                isInsideRoot = true;
            }

            if (!isInsideRoot) continue;

            if (file.isDirectory()) {
                try {
                    Collections.addAll(pending, file.listFiles());
                } catch (SecurityException | NullPointerException e) {
                    // skip unreadable directories
                }
            } else if (file.getName().toLowerCase().contains(query.toLowerCase())) {
                includeFile(result, null, file);
            }
        }
        return result;
    }

    @Override
    public boolean isChildDocument(String parentDocumentId, String documentId) {
        try {
            final String parent = new File(parentDocumentId).getCanonicalPath();
            final String child  = new File(documentId).getCanonicalPath();
            return child.startsWith(parent + "/");
        } catch (IOException e) {
            return false;
        }
    }

    @Override
    public ParcelFileDescriptor openDocument(String documentId, String mode, CancellationSignal signal)
            throws FileNotFoundException {
        return ParcelFileDescriptor.open(getFileForDocId(documentId),
            ParcelFileDescriptor.parseMode(mode));
    }

    @Override
    public String createDocument(String parentDocumentId, String mimeType, String displayName)
            throws FileNotFoundException {
        File parent = getFileForDocId(parentDocumentId);
        File newFile = new File(parent, displayName);

        // avoid collisions
        int suffix = 2;
        while (newFile.exists())
            newFile = new File(parent, displayName + " (" + suffix++ + ")");

        try {
            boolean ok = Document.MIME_TYPE_DIR.equals(mimeType)
                ? newFile.mkdir()
                : newFile.createNewFile();
            if (!ok)
                throw new FileNotFoundException("Failed to create: " + newFile.getPath());
        } catch (IOException e) {
            throw new FileNotFoundException("Failed to create: " + newFile.getPath());
        }
        return newFile.getAbsolutePath();
    }

    @Override
    public void deleteDocument(String documentId) throws FileNotFoundException {
        if (!deleteRecursive(getFileForDocId(documentId)))
            throw new FileNotFoundException("Failed to delete: " + documentId);
    }

    @Override
    public String getDocumentType(String documentId) throws FileNotFoundException {
        return getMimeType(getFileForDocId(documentId));
    }

    // Helpers

    private static File getFileForDocId(String docId) throws FileNotFoundException {
        if (modFolder == null)
            throw new FileNotFoundException("Provider not initialized");
        final File f = (docId == null || docId.isEmpty()) ? modFolder : new File(docId);
        if (!f.exists())
            throw new FileNotFoundException(f.getAbsolutePath() + " not found");
        return f;
    }

    private void includeFile(MatrixCursor result, String docId, File file) throws FileNotFoundException {
        if (docId == null)
            docId = file.getAbsolutePath();
        else
            file = getFileForDocId(docId);

        int flags = 0;
        if (file.isDirectory()) {
            if (file.canWrite()) flags |= Document.FLAG_DIR_SUPPORTS_CREATE;
        } else if (file.canWrite()) {
            flags |= Document.FLAG_SUPPORTS_WRITE;
        }
        if (file.getParentFile() != null && file.getParentFile().canWrite())
            flags |= Document.FLAG_SUPPORTS_DELETE;

        final String mimeType = getMimeType(file);
        if (mimeType.startsWith("image/"))
            flags |= Document.FLAG_SUPPORTS_THUMBNAIL;

        final MatrixCursor.RowBuilder row = result.newRow();
        row.add(Document.COLUMN_DOCUMENT_ID,   docId);
        row.add(Document.COLUMN_DISPLAY_NAME,  file.getName());
        row.add(Document.COLUMN_SIZE,          file.length());
        row.add(Document.COLUMN_MIME_TYPE,     mimeType);
        row.add(Document.COLUMN_LAST_MODIFIED, file.lastModified());
        row.add(Document.COLUMN_FLAGS,         flags);
    }

    private static String getMimeType(File file) {
        if (file == null || file.isDirectory()) return Document.MIME_TYPE_DIR;
        final String name = file.getName();
        final int lastDot = name.lastIndexOf('.');
        if (lastDot >= 0) {
            final String mime = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(name.substring(lastDot + 1).toLowerCase());
            if (mime != null) return mime;
        }
        return "application/octet-stream";
    }

    private static boolean deleteRecursive(File file) {
        if (file.isDirectory()) {
            File[] children = null;
            try { children = file.listFiles(); } catch (SecurityException e) { /* skip */ }
            if (children != null) {
                for (File child : children)
                    if (!deleteRecursive(child)) return false;
            }
        }
        return file.delete();
    }
}
