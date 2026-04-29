package com.lm.login_test.utils;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public final class WavFileUtil {
    private static final int SAMPLE_RATE = 16000;
    private static final int BITS_PER_SAMPLE = 16;
    private static final int CHANNELS = 1;

    private WavFileUtil() {
    }

    public static byte[] pcmToWavBytes(byte[] pcmData) throws IOException {
        byte[] safePcmData = pcmData == null ? new byte[0] : pcmData;
        try (ByteArrayOutputStream output = new ByteArrayOutputStream();
             DataOutputStream dataOutputStream = new DataOutputStream(output)) {
            writeWavHeader(dataOutputStream, safePcmData.length);
            dataOutputStream.write(safePcmData);
            dataOutputStream.flush();
            return output.toByteArray();
        }
    }

    private static void writeWavHeader(DataOutputStream output, int pcmDataLength) throws IOException {
        int totalDataLength = pcmDataLength + 36;
        int byteRate = SAMPLE_RATE * CHANNELS * BITS_PER_SAMPLE / 8;

        output.writeBytes("RIFF");
        writeIntLittleEndian(output, totalDataLength);
        output.writeBytes("WAVE");

        output.writeBytes("fmt ");
        writeIntLittleEndian(output, 16);
        writeShortLittleEndian(output, (short) 1);
        writeShortLittleEndian(output, (short) CHANNELS);
        writeIntLittleEndian(output, SAMPLE_RATE);
        writeIntLittleEndian(output, byteRate);
        writeShortLittleEndian(output, (short) (CHANNELS * BITS_PER_SAMPLE / 8));
        writeShortLittleEndian(output, (short) BITS_PER_SAMPLE);

        output.writeBytes("data");
        writeIntLittleEndian(output, pcmDataLength);
    }

    private static void writeIntLittleEndian(DataOutputStream output, int value) throws IOException {
        output.write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(value).array());
    }

    private static void writeShortLittleEndian(DataOutputStream output, short value) throws IOException {
        output.write(ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort(value).array());
    }
}
