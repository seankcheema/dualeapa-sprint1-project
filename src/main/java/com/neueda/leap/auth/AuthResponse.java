package com.neueda.leap.auth;

import java.time.OffsetDateTime;
import java.util.UUID;

public record AuthResponse(
        UUID sessionId,
        OffsetDateTime expiresAt
) {
}
