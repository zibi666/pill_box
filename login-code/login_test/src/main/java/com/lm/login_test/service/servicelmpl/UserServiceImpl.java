package com.lm.login_test.service.servicelmpl;

import com.lm.login_test.domain.User;
import com.lm.login_test.repository.UserDao;
import com.lm.login_test.service.UserService;
import jakarta.annotation.Resource;
import jakarta.transaction.Transactional;
import org.springframework.stereotype.Service;

@Service
public class UserServiceImpl implements UserService {
    @Resource
    private UserDao userDao;
    @Override
    public User loginService(String uname, String password) {
        // 如果账号密码都对则返回登录的用户对象，若有一个错误则返回null
        User user = userDao.findByUnameAndPassword(uname, password);
        // 重要信息置空
        if(user != null){
            user.setPassword("");
        }
        return user;
    }

    @Override
    public User registService(User user) {
        //当新用户的用户名已存在时
        if(userDao.findByUname(user.getUname())!=null){
            // 无法注册
            return null;
        }else{
            //返回创建好的用户对象(带uid)
            User newUser = userDao.save(user);
            if(newUser != null){
                newUser.setPassword("");
            }
            return newUser;
        }
    }

    // ➕ 修改用户名
    @Override
    @Transactional
    public boolean updateUsername(String oldUsername, String newUsername) {
        // 1. 检查旧用户名是否存在
        User user = userDao.findByUname(oldUsername);
        if (user == null) {
            throw new RuntimeException("旧用户名不存在");
        }

        // 2. 检查新用户名是否已被占用
        User existingUser = userDao.findByUname(newUsername);
        if (existingUser != null) {
            throw new RuntimeException("新用户名已被占用");
        }

        // 3. 更新用户名
        user.setUname(newUsername);
        userDao.save(user);
        return true;
    }

    // ➕ 修改密码
    @Override
    @Transactional
    public boolean updatePassword(String username, String oldPassword, String newPassword) {
        // 1. 根据用户名查找用户
        User user = userDao.findByUname(username);
        if (user == null) {
            throw new RuntimeException("用户不存在");
        }

        // 2. 验证旧密码
        if (!user.getPassword().equals(oldPassword)) {
            throw new RuntimeException("旧密码错误");
        }

        // 3. 更新密码
        user.setPassword(newPassword);
        userDao.save(user);
        return true;
    }
    @Override
    public Long getUidByUname(String uname) {
        User user = userDao.findByUname(uname);
        return user != null ? user.getUid() : null;
    }

}
