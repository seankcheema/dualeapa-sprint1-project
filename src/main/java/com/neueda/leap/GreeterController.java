package com.neueda.leap;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class GreeterController {

    private final Greeter greeter;

    public GreeterController(Greeter greeter) {
        this.greeter = greeter;
    }

    @GetMapping("/api/greet")
    public String greet(@RequestParam(defaultValue = "Trader") String name) {
        return greeter.greet(name);
    }
}
