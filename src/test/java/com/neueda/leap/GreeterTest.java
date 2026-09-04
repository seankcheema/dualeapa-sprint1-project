package com.neueda.leap;

import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

@Tag("unit")
class GreeterTest {

    private final Greeter greeter = new Greeter();

    @Test
    void greetReturnsGreetingWithName() {
        assertThat(greeter.greet("Trader")).isEqualTo("Good day, Trader");
    }
}
