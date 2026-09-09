package com.neueda.leap;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Trading Platform - Business Backend Application
 * 
 * Main entry point for the Spring Boot application.
 * Flyway migrations will run automatically on startup.
 */
@SpringBootApplication
public class TradingPlatformApplication {

    public static void main(String[] args) {
        SpringApplication.run(TradingPlatformApplication.class, args);
    }
}
