package com.lm.login_test.dto;

public class UpdatePasswordRequest {
    private String username;
    private String oldPassword;
    private String newPassword;

    // 必须有无参构造函数
    public UpdatePasswordRequest() {}

    // Getter和Setter方法
    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getOldPassword() {
        return oldPassword;
    }

    public void setOldPassword(String oldPassword) {
        this.oldPassword = oldPassword;
    }

    public String getNewPassword() {
        return newPassword;
    }

    public void setNewPassword(String newPassword) {
        this.newPassword = newPassword;
    }
}