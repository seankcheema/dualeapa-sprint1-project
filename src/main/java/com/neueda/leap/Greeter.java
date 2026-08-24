package com.neueda.leap;

import org.springframework.stereotype.Service;

@Service
public class Greeter {
    public String greet(String name) {
        return "Good day, " + name;
    }
}
