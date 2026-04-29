package com.lm.login_test.controller;


import com.lm.login_test.domain.User;
import com.lm.login_test.dto.UpdatePasswordRequest;
import com.lm.login_test.service.UserService;
import com.lm.login_test.utils.Result;
import jakarta.annotation.Resource;
import org.springframework.web.bind.annotation.*;
import com.lm.login_test.dto.UpdateUsernameRequest;

@RestController
@RequestMapping("/user")
public class UserController {
    @Resource
    private UserService userService;
    @PostMapping("/login")
//    public Result<User> loginController(@RequestParam String uname, @RequestParam String password){
//        User user = userService.loginService(uname, password);
//        if(user!=null){
//            return Result.success(user,"登录成功！");
//        }else{
//            return Result.error("123","账号或密码错误！");
//        }
//    }
    public Result<User> loginController(@RequestBody User user) { //改这里！
        // user.getUname(), user.getPassword() 可直接使用
        User foundUser = userService.loginService(user.getUname(), user.getPassword());
        if (foundUser != null) {
            return Result.success(foundUser, "登录成功！");
        } else {
            return Result.error("123", "账号或密码错误！");
        }
    }

    @PostMapping("/register")
    public Result<User> registController(@RequestBody User newUser){
        User user = userService.registService(newUser);
        if(user!=null){
            return Result.success(user,"注册成功！");
        }else{
            return Result.error("456","用户名已存在！");
        }
    }


    //修改用户名（已修复 Long 类型）
    @PostMapping("/updateUsername")
    public Result<String> updateUsername(@RequestBody UpdateUsernameRequest request) {
        String oldUsername = request.getOldUsername();
        String newUsername = request.getNewUsername();

        if (oldUsername == null || oldUsername.trim().isEmpty()) {
            return Result.error("400", "旧用户名不能为空");
        }
        if (newUsername == null || newUsername.trim().isEmpty()) {
            return Result.error("400", "新用户名不能为空");
        }

        try {
            boolean success = userService.updateUsername(oldUsername, newUsername);
            if (success) {
                return Result.success("用户名修改成功");
            } else {
                return Result.error("500", "未知错误");
            }
        } catch (Exception e) {
            return Result.error("400", e.getMessage()); // ← 能正确显示“旧用户名不存在”
        }
    }

    //修改密码（补全方法签名 + 参数 + 改为 Long）
    @PostMapping("/updatePassword")
    public Result<String> updatePassword(@RequestBody UpdatePasswordRequest request) {
        String username = request.getUsername();
        String oldPassword = request.getOldPassword();
        String newPassword = request.getNewPassword();

        // 参数校验
        if (username == null || username.trim().isEmpty()) {
            return Result.error("400", "用户名不能为空");
        }
        if (oldPassword == null || oldPassword.trim().isEmpty()) {
            return Result.error("400", "旧密码不能为空");
        }
        if (newPassword == null || newPassword.trim().isEmpty()) {
            return Result.error("400", "新密码不能为空");
        }

        try {
            boolean success = userService.updatePassword(username, oldPassword, newPassword);
            if (success) {
                return Result.success("密码修改成功");
            } else {
                return Result.error("400", "修改失败：用户名不存在或旧密码错误");
            }
        } catch (Exception e) {
            return Result.error("500", "系统错误：" + e.getMessage());
        }
    }

    @GetMapping("/getUid")
    public Result<Long> getUidByUname(@RequestParam String uname) {
        Long uid = userService.getUidByUname(uname);
        if (uid != null) {
            return Result.success(uid, "获取成功");
        } else {
            return Result.error("404", "用户不存在");
        }
    }
}
