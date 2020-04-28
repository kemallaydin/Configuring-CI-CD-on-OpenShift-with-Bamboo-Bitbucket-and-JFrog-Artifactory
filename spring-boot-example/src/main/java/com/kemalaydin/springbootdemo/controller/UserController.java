package com.kemalaydin.springbootdemo.controller;

import com.kemalaydin.springbootdemo.entity.User;
import com.kemalaydin.springbootdemo.service.UserService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
public class UserController {

    private final UserService userService;

    @Autowired
    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping(path = "/users")
    public List<User> findAll() {
        return this.userService.findAll();
    }
}
