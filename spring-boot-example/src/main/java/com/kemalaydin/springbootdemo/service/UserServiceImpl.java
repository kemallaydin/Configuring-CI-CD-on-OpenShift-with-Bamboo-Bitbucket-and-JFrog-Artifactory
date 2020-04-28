package com.kemalaydin.springbootdemo.service;

import com.kemalaydin.springbootdemo.entity.User;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

@Service
public class UserServiceImpl implements UserService {
    private List<User> userList;

    public UserServiceImpl() {
        this.userList = new ArrayList<>();
        userList.add(new User(1, "Kemal", "Aydın"));
        userList.add(new User(2, "Kemal", "Aydın"));
        userList.add(new User(3, "Kemal", "Aydın"));
    }

    @Override
    public List<User> findAll() {
        return this.userList;
    }
}
