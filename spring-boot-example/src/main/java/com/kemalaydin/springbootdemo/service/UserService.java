package com.kemalaydin.springbootdemo.service;

import com.kemalaydin.springbootdemo.entity.User;

import java.util.List;

public interface UserService {
    List<User> findAll();
}
