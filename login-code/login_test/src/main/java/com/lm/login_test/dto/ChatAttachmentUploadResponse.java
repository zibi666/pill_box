package com.lm.login_test.dto;

public class ChatAttachmentUploadResponse {
    private String id;
    private String fileName;
    private long size;
    private String contentType;
    private boolean textAvailable;

    public ChatAttachmentUploadResponse() {
    }

    public ChatAttachmentUploadResponse(String id, String fileName, long size, String contentType, boolean textAvailable) {
        this.id = id;
        this.fileName = fileName;
        this.size = size;
        this.contentType = contentType;
        this.textAvailable = textAvailable;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getFileName() {
        return fileName;
    }

    public void setFileName(String fileName) {
        this.fileName = fileName;
    }

    public long getSize() {
        return size;
    }

    public void setSize(long size) {
        this.size = size;
    }

    public String getContentType() {
        return contentType;
    }

    public void setContentType(String contentType) {
        this.contentType = contentType;
    }

    public boolean isTextAvailable() {
        return textAvailable;
    }

    public void setTextAvailable(boolean textAvailable) {
        this.textAvailable = textAvailable;
    }
}
