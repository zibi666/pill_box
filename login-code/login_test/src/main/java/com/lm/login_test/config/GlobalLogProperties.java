package com.lm.login_test.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "global.log")
public class GlobalLogProperties {
    private Coze coze = new Coze();
    private Embedded embedded = new Embedded();

    public Coze getCoze() {
        return coze;
    }

    public void setCoze(Coze coze) {
        this.coze = coze == null ? new Coze() : coze;
    }

    public Embedded getEmbedded() {
        return embedded;
    }

    public void setEmbedded(Embedded embedded) {
        this.embedded = embedded == null ? new Embedded() : embedded;
    }

    public static class Coze {
        private boolean captureEnabled = false;
        private int captureMaxLength = 4000;

        public boolean isCaptureEnabled() {
            return captureEnabled;
        }

        public void setCaptureEnabled(boolean captureEnabled) {
            this.captureEnabled = captureEnabled;
        }

        public int getCaptureMaxLength() {
            return captureMaxLength;
        }

        public void setCaptureMaxLength(int captureMaxLength) {
            this.captureMaxLength = captureMaxLength;
        }
    }

    public static class Embedded {
        private boolean cozeReplyEnabled = false;

        public boolean isCozeReplyEnabled() {
            return cozeReplyEnabled;
        }

        public void setCozeReplyEnabled(boolean cozeReplyEnabled) {
            this.cozeReplyEnabled = cozeReplyEnabled;
        }
    }
}
