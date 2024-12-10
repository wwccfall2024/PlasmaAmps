-- Create your tables, views, functions and procedures here!
CREATE SCHEMA social;
USE social;

CREATE TABLE users (
  user_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  first_name VARCHAR(50) NOT NULL,
  last_name VARCHAR(50) NOT NULL,
  email VARCHAR(100) NOT NULL,
  created_on DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sessions (
  session_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id INT UNSIGNED,
  created_on DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_on DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON DELETE SET NULL
    ON UPDATE CASCADE
);

CREATE TABLE friends (
  user_friend_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id INT UNSIGNED,
  friend_id INT UNSIGNED,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON DELETE SET NULL  --might need to change if causes problems/likely issue maker
    ON UPDATE CASCADE,
  FOREIGN KEY (friend_id) REFERENCES users(user_id)
    ON DELETE SET NULL  --might need to change if causes problems/likely issue maker
    ON UPDATE CASCADE
);

CREATE TABLE posts (
  post_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id INT UNSIGNED,
  created_on DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_on DATETIME DEFAULT CURRENT_TIMESTAMP,
  content TEXT,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON DELETE SET NULL
    ON UPDATE CASCADE
);

CREATE TABLE notifications (
  notification_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id INT UNSIGNED,
  post_id INT UNSIGNED,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON DELETE SET NULL
    ON UPDATE CASCADE,
  FOREIGN KEY (post_id) REFERENCES posts(post_id)
    ON DELETE SET NULL
    ON UPDATE CASCADE
);





-- THIS IS TO SEPERATE TABLES AND VIEWS TO HELP ME FIND THEM WHEN DEBUGGING





CREATE VIEW notification_posts AS
SELECT 
    n.user_id,
    u.first_name,
    u.last_name,
    p.post_id,
    p.content
FROM 
    notifications n
LEFT INNER JOIN posts p ON n.post_id = p.post_id
LEFT INNER JOIN users u ON p.user_id = u.user_id;




-- THIS IS TO SEPERATE VIEWS AND STORED PROGRAMS




CREATE TRIGGER after_user_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO notifications (user_id, post_id)
    SELECT user_id, NULL 
    FROM users
    WHERE user_id != NEW.user_id;
END;



CREATE EVENT cleanup_sessions
ON SCHEDULE EVERY 10 SECOND
DO
    DELETE FROM sessions
    WHERE updated_on < NOW() - INTERVAL 2 HOUR;


DELIMITER $$
CREATE PROCEDURE add_post(IN userId INT, IN postContent TEXT)
BEGIN
    -- Insert the new post
    INSERT INTO posts (user_id, content, created_on, updated_on)
    VALUES (userId, postContent, NOW(), NOW());

    -- Get the post_id of the newly created post
    SET @new_post_id = LAST_INSERT_ID();

    -- Notify all friends of the user
    INSERT INTO notifications (user_id, post_id)
    SELECT friend_id, @new_post_id
    FROM friends
    WHERE user_id = userId;
END;
$$
DELIMITER ;


