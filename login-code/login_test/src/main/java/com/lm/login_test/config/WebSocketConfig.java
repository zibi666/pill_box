package com.lm.login_test.config;

import com.lm.login_test.websocket.AppAsrWebSocketHandler;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.config.annotation.EnableWebSocket;
import org.springframework.web.socket.config.annotation.WebSocketConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketHandlerRegistry;

@Configuration
@EnableWebSocket
public class WebSocketConfig implements WebSocketConfigurer {
    private final AppAsrWebSocketHandler appAsrWebSocketHandler;

    public WebSocketConfig(AppAsrWebSocketHandler appAsrWebSocketHandler) {
        this.appAsrWebSocketHandler = appAsrWebSocketHandler;
    }

    @Override
    public void registerWebSocketHandlers(WebSocketHandlerRegistry registry) {
        registry.addHandler(appAsrWebSocketHandler, "/app-asr").setAllowedOrigins("*");
    }
}
