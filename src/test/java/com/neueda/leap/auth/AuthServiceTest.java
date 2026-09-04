package com.neueda.leap.auth;

import com.neueda.leap.user.SessionRepository;
import com.neueda.leap.user.User;
import com.neueda.leap.user.UserRepository;
import com.neueda.leap.user.UserSession;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@Tag("unit")
class AuthServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private SessionRepository sessionRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    private AuthService authService;

    @BeforeEach
    void setUp() {
        authService = new AuthService(userRepository, sessionRepository, passwordEncoder);
    }

    private static RegisterRequest registerRequest(String username, String email) {
        return new RegisterRequest(username, email, "password123", "123-45-6789", LocalDate.of(1990, 1, 1));
    }

    private static User activeUser(String username, String passwordHash) {
        User user = new User();
        user.setUserId(java.util.UUID.randomUUID());
        user.setUsername(username);
        user.setPasswordHash(passwordHash);
        user.setAccountStatus("ACTIVE");
        user.setFailedLoginAttempts(0);
        user.setSessionTimeoutMinutes(10);
        return user;
    }

    @Test
    void registerCreatesUserWhenUsernameAndEmailAreFree() {
        when(userRepository.existsByUsername("alice")).thenReturn(false);
        when(userRepository.existsByEmail("alice@example.com")).thenReturn(false);
        when(passwordEncoder.encode("password123")).thenReturn("hashed");
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));

        User result = authService.register(registerRequest("alice", "alice@example.com"));

        assertThat(result.getUsername()).isEqualTo("alice");
        assertThat(result.getEmail()).isEqualTo("alice@example.com");
        assertThat(result.getPasswordHash()).isEqualTo("hashed");
        assertThat(result.getUserId()).isNotNull();
        assertThat(result.getCreatedAt()).isNotNull();
    }

    @Test
    void registerThrowsConflictWhenUsernameIsTaken() {
        when(userRepository.existsByUsername("alice")).thenReturn(true);

        assertThatThrownBy(() -> authService.register(registerRequest("alice", "alice@example.com")))
                .isInstanceOf(ConflictException.class)
                .hasMessage("Username is already taken");

        verify(userRepository, never()).existsByEmail(any());
        verify(userRepository, never()).save(any());
    }

    @Test
    void registerThrowsConflictWhenEmailIsTaken() {
        when(userRepository.existsByUsername("alice")).thenReturn(false);
        when(userRepository.existsByEmail("alice@example.com")).thenReturn(true);

        assertThatThrownBy(() -> authService.register(registerRequest("alice", "alice@example.com")))
                .isInstanceOf(ConflictException.class)
                .hasMessage("Email is already registered");

        verify(userRepository, never()).save(any());
    }

    @Test
    void loginSucceedsAndIssuesSessionForCorrectCredentials() {
        User user = activeUser("alice", "hashed");
        when(userRepository.findByUsername("alice")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("password123", "hashed")).thenReturn(true);
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(sessionRepository.save(any(UserSession.class))).thenAnswer(invocation -> invocation.getArgument(0));

        UserSession session = authService.login(new LoginRequest("alice", "password123"));

        assertThat(session.getUserId()).isEqualTo(user.getUserId());
        assertThat(session.getExpiresAt()).isAfter(session.getIssuedAt());
        assertThat(user.getFailedLoginAttempts()).isZero();
        assertThat(user.getLockedUntil()).isNull();
        assertThat(user.getLastLoginAt()).isNotNull();
    }

    @Test
    void loginThrowsUnauthorizedForUnknownUsername() {
        when(userRepository.findByUsername("ghost")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> authService.login(new LoginRequest("ghost", "password123")))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessage("Invalid username or password");

        verify(sessionRepository, never()).save(any());
    }

    @Test
    void loginThrowsUnauthorizedForInactiveAccount() {
        User user = activeUser("alice", "hashed");
        user.setAccountStatus("SUSPENDED");
        when(userRepository.findByUsername("alice")).thenReturn(Optional.of(user));

        assertThatThrownBy(() -> authService.login(new LoginRequest("alice", "password123")))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessage("Account is not active");
    }

    @Test
    void loginThrowsUnauthorizedWhileAccountIsLocked() {
        User user = activeUser("alice", "hashed");
        user.setLockedUntil(OffsetDateTime.now().plusMinutes(5));
        when(userRepository.findByUsername("alice")).thenReturn(Optional.of(user));

        assertThatThrownBy(() -> authService.login(new LoginRequest("alice", "password123")))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessage("Account is temporarily locked due to failed login attempts");
    }

    @Test
    void loginWithWrongPasswordIncrementsFailedAttemptsWithoutLocking() {
        User user = activeUser("alice", "hashed");
        user.setFailedLoginAttempts(0);
        when(userRepository.findByUsername("alice")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("wrong", "hashed")).thenReturn(false);

        assertThatThrownBy(() -> authService.login(new LoginRequest("alice", "wrong")))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessage("Invalid username or password");

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        assertThat(captor.getValue().getFailedLoginAttempts()).isEqualTo(1);
        assertThat(captor.getValue().getLockedUntil()).isNull();
    }

    @Test
    void loginLocksAccountOnFifthFailedAttempt() {
        User user = activeUser("alice", "hashed");
        user.setFailedLoginAttempts(4);
        when(userRepository.findByUsername("alice")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("wrong", "hashed")).thenReturn(false);

        assertThatThrownBy(() -> authService.login(new LoginRequest("alice", "wrong")))
                .isInstanceOf(UnauthorizedException.class);

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        assertThat(captor.getValue().getFailedLoginAttempts()).isEqualTo(5);
        assertThat(captor.getValue().getLockedUntil()).isAfter(OffsetDateTime.now());
    }

    @Test
    void loginSucceedsAfterLockoutHasExpired() {
        User user = activeUser("alice", "hashed");
        user.setLockedUntil(OffsetDateTime.now().minusMinutes(1));
        when(userRepository.findByUsername("alice")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("password123", "hashed")).thenReturn(true);
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(sessionRepository.save(any(UserSession.class))).thenAnswer(invocation -> invocation.getArgument(0));

        UserSession session = authService.login(new LoginRequest("alice", "password123"));

        assertThat(session).isNotNull();
        assertThat(user.getLockedUntil()).isNull();
    }
}
