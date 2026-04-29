package com.lm.login_test.utils;

import net.sourceforge.pinyin4j.PinyinHelper;

public final class PinyinUtils {
    private PinyinUtils() {
    }

    public static String toPinyin(String text) {
        if (text == null || text.isBlank()) {
            return "";
        }

        StringBuilder builder = new StringBuilder();
        for (char ch : text.toCharArray()) {
            builder.append(toPinyinToken(ch));
        }
        return builder.toString().toLowerCase();
    }

    public static String toNasalInsensitivePinyin(String text) {
        return normalizeNasalFinals(toPinyin(text));
    }

    public static String toPinyinToken(char ch) {
        if (Character.toString(ch).matches("[\\u4E00-\\u9FA5]")) {
            String[] pinyin = PinyinHelper.toHanyuPinyinStringArray(ch);
            if (pinyin != null && pinyin.length > 0) {
                return pinyin[0].replaceAll("[^a-zA-Z]", "").toLowerCase();
            }
        }

        if (Character.isLetterOrDigit(ch)) {
            return String.valueOf(Character.toLowerCase(ch));
        }
        return "";
    }

    public static String normalizeNasalFinals(String pinyin) {
        if (pinyin == null || pinyin.isBlank()) {
            return "";
        }
        return pinyin.toLowerCase()
                .replace("iang", "ian")
                .replace("uang", "uan")
                .replace("ang", "an")
                .replace("eng", "en")
                .replace("ing", "in")
                .replace("ong", "on");
    }
}
