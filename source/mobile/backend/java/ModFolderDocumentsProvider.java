package mobile.backend.java;

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
    private static final String ROOT_ID   = "mod_folder_root";

    private static final String[] DEFAULT_ROOT_PROJECTION = new String[]{
        Root.COLUMN_ROOT_ID,
        Root.COLUMN_MIME_TYPES,
        Root.COLUMN_FLAGS,
        Root.COLUMN_ICON,
        Root.COLUMN_TITLE,
        Root.COLUMN_DOCUMENT_ID,
        Root.COLUMN_AVAILABLE_BYTES,
    };

    private static final String[] DEFAULT_DOCUMENT_PROJECTION = new String[]{
        Document.COLUMN_DOCUMENT_ID,
        Document.COLUMN_MIME_TYPE,
        Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_LAST_MODIFIED,
        Document.COLUMN_FLAGS,
        Document.COLUMN_SIZE,
    };

    private File getModFolder() {
        return new File(Environment.getExternalStorageDirectory(), ".ImpostorLegacy");
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Cursor queryRoots(String[] projection) {
        final MatrixCursor result = new MatrixCursor(
            projection != null ? projection : DEFAULT_ROOT_PROJECTION
        );

        final File modFolder = getModFolder();
        if (!modFolder.exists()) modFolder.mkdirs();

        final MatrixCursor.RowBuilder row = result.newRow();
        row.add(Root.COLUMN_ROOT_ID, ROOT_ID);
        row.add(Root.COLUMN_DOCUMENT_ID, getDocumentId(modFolder));
        row.add(Root.COLUMN_TITLE, "VS Impostor Legacy");
        row.add(Root.COLUMN_ICON, getContext().getApplicationInfo().icon);
        row.add(Root.COLUMN_FLAGS,
            Root.FLAG_SUPPORTS_CREATE |
            Root.FLAG_SUPPORTS_SEARCH |
            Root.FLAG_LOCAL_ONLY);
        row.add(Root.COLUMN_MIME_TYPES, "*/*");
        row.add(Root.COLUMN_AVAILABLE_BYTES, modFolder.getFreeSpace());
        return result;
    }

    @Override
    public Cursor queryDocument(String documentId, String[] projection) throws FileNotFoundException {
        final MatrixCursor result = new MatrixCursor(
            projection != null ? projection : DEFAULT_DOCUMENT_PROJECTION
        );
        includeFile(result, getFileForDocId(documentId));
        return result;
    }

    @Override
    public Cursor queryChildDocuments(String parentDocumentId, String[] projection, String sortOrder) throws FileNotFoundException {
        final MatrixCursor result = new MatrixCursor(
            projection != null ? projection : DEFAULT_DOCUMENT_PROJECTION
        );
        final File parent = getFileForDocId(parentDocumentId);
        if (parent.isDirectory()) {
            for (File child : parent.listFiles()) {
                includeFile(result, child);
            }
        }
        return result;
    }

    @Override
    public ParcelFileDescriptor openDocument(String documentId, String mode, CancellationSignal signal)
            throws FileNotFoundException {
        final File file = getFileForDocId(documentId);
        final int accessMode = ParcelFileDescriptor.parseMode(mode);
        return ParcelFileDescriptor.open(file, accessMode);
    }

    @Override
    public String createDocument(String parentDocumentId, String mimeType, String displayName)
            throws FileNotFoundException {
        final File parent = getFileForDocId(parentDocumentId);
        final File newFile = new File(parent, displayName);
        if (Document.MIME_TYPE_DIR.equals(mimeType)) {
            if (!newFile.mkdirs()) throw new FileNotFoundException("Could not create directory: " + newFile);
        } else {
            try {
                if (!newFile.createNewFile()) throw new FileNotFoundException("File already exists: " + newFile);
            } catch (IOException e) {
                throw new FileNotFoundException("Could not create file: " + e.getMessage());
            }
        }
        return getDocumentId(newFile);
    }

    @Override
    public void deleteDocument(String documentId) throws FileNotFoundException {
        final File file = getFileForDocId(documentId);
        if (!deleteFile(file)) throw new FileNotFoundException("Could not delete: " + file);
    }

    // Helpers

    private String getDocumentId(File file) {
        final String rootPath = getModFolder().getAbsolutePath();
        final String filePath = file.getAbsolutePath();
        if (rootPath.equals(filePath)) return ROOT_ID;
        return ROOT_ID + ":" + filePath.substring(rootPath.length() + 1);
    }

    private File getFileForDocId(String docId) throws FileNotFoundException {
        final File root = getModFolder();
        if (ROOT_ID.equals(docId)) return root;
        final int splitAt = docId.indexOf(':', ROOT_ID.length());
        if (splitAt < 0) throw new FileNotFoundException("Bad document ID: " + docId);
        final String path = docId.substring(splitAt + 1);
        final File file = new File(root, path);
        if (!file.exists()) throw new FileNotFoundException("File not found: " + file);
        return file;
    }

    private void includeFile(MatrixCursor result, File file) {
        final MatrixCursor.RowBuilder row = result.newRow();
        row.add(Document.COLUMN_DOCUMENT_ID, getDocumentId(file));
        row.add(Document.COLUMN_DISPLAY_NAME, file.getName());
        row.add(Document.COLUMN_LAST_MODIFIED, file.lastModified());
        row.add(Document.COLUMN_SIZE, file.length());

        if (file.isDirectory()) {
            row.add(Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR);
            row.add(Document.COLUMN_FLAGS,
                Document.FLAG_DIR_SUPPORTS_CREATE |
                Document.FLAG_SUPPORTS_DELETE);
        } else {
            row.add(Document.COLUMN_MIME_TYPE, getMimeType(file));
            row.add(Document.COLUMN_FLAGS,
                Document.FLAG_SUPPORTS_WRITE |
                Document.FLAG_SUPPORTS_DELETE);
        }
    }

    private String getMimeType(File file) {
        final String name = file.getName();
        final int lastDot = name.lastIndexOf('.');
        if (lastDot >= 0) {
            final String ext = name.substring(lastDot + 1).toLowerCase();
            final String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
            if (mime != null) return mime;
        }
        return "application/octet-stream";
    }

    private boolean deleteFile(File file) {
        if (file.isDirectory()) {
            for (File child : file.listFiles()) {
                if (!deleteFile(child)) return false;
            }
        }
        return file.delete();
    }
}
