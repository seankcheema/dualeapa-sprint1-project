package com.neueda.leap.auth;

import com.neueda.leap.user.User;
import com.neueda.leap.user.UserSession;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@Tag("unit")
class AuthControllerUnitTest {

    @Mock
    private AuthService authService;

    private AuthController authController;

    @BeforeEach
    void setUp() {
        authController = new AuthController(authService);
    }

    @Test
    void registerReturnsResponseBuiltFromServiceResult() {
        RegisterRequest request = new RegisterRequest(
                "alice", "alice@example.com", "password123", "Alice", null, "Anderson", "123-45-6789", "1 Main St",
                LocalDate.of(1990, 1, 1));
        User user = new User();
        user.setUserId(UUID.randomUUID());
        user.setUsername("alice");
        user.setEmail("alice@example.com");
        when(authService.register(request)).thenReturn(user);

        RegisterResponse response = authController.register(request);

        assertThat(response.userId()).isEqualTo(user.getUserId());
        assertThat(response.username()).isEqualTo("alice");
        assertThat(response.email()).isEqualTo("alice@example.com");
    }

    @Test
    void loginReturnsResponseBuiltFromServiceResult() {
        LoginRequest request = new LoginRequest("alice", "password123");
        UserSession session = new UserSession();
        session.setSessionId(UUID.randomUUID());
        session.setExpiresAt(OffsetDateTime.now().plusMinutes(10));
        when(authService.login(request)).thenReturn(session);

        AuthResponse response = authController.login(request);

        assertThat(response.sessionId()).isEqualTo(session.getSessionId());
        assertThat(response.expiresAt()).isEqualTo(session.getExpiresAt());
    }

    @Test
    void registerPropagatesConflictExceptionFromService() {
        RegisterRequest request = new RegisterRequest(
                "alice", "alice@example.com", "password123", "Alice", null, "Anderson", "123-45-6789", "1 Main St",
                LocalDate.of(1990, 1, 1));
        when(authService.register(request)).thenThrow(new ConflictException("Username is already taken"));

        assertThatThrownBy(() -> authController.register(request)).isInstanceOf(ConflictException.class);
    }

    @Test
    void loginPropagatesUnauthorizedExceptionFromService() {
        LoginRequest request = new LoginRequest("alice", "wrong");
        when(authService.login(request)).thenThrow(new UnauthorizedException("Invalid username or password"));

        assertThatThrownBy(() -> authController.login(request)).isInstanceOf(UnauthorizedException.class);
    }
}
