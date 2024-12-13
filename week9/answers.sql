-- Create your tables, views, functions and procedures here!
CREATE SCHEMA social;
USE social;

CREATE TABLE users (
  user_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT NOT NULL,
  first_name VARCHAR(50) NOT NULL,
  last_name VARCHAR(50) NOT NULL,
  email VARCHAR(100) NOT NULL,
  created_on DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE sessions (
  session_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT NOT NULL,
  user_id INT UNSIGNED NOT NULL,
  created_on DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_on DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE friends (
  user_friend_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  friend_id INT UNSIGNED,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON DELETE CASCADE  
    ON UPDATE CASCADE,
  FOREIGN KEY (friend_id) REFERENCES users(user_id)
    ON DELETE CASCADE  
    ON UPDATE CASCADE
);

CREATE TABLE posts (
  post_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  created_on DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_on DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
  content TEXT,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE notifications (
  notification_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id INT UNSIGNED,
  post_id INT UNSIGNED,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  FOREIGN KEY (post_id) REFERENCES posts(post_id)
    ON DELETE CASCADE
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
INNER JOIN posts p ON n.post_id = p.post_id
INNER JOIN users u ON p.user_id = u.user_id;




-- THIS IS TO SEPERATE VIEWS AND STORED PROGRAMS




DELIMITER $$

CREATE TRIGGER after_user_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE cur_user_id INT;

    -- Declare a cursor for selecting all user_ids except the new user
    DECLARE user_cursor CURSOR FOR 
    SELECT user_id 
    FROM users 
    WHERE user_id != NEW.user_id;

    -- Declare a handler for the end of the cursor
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    -- Create a new post for the new user
    INSERT INTO posts (user_id, content, created_on, updated_on)
    VALUES (NEW.user_id, CONCAT(NEW.first_name, ' ', NEW.last_name, ' just joined!'), NOW(), NOW());

    -- Get the newly created post_id
    SET @new_post_id = LAST_INSERT_ID();

    -- Open the cursor
    OPEN user_cursor;

    -- Fetch the first user_id into the cursor variable
    FETCH user_cursor INTO cur_user_id;

    -- Loop through each user_id
    WHILE done = 0 DO
        -- Insert a notification for the current user
        INSERT INTO notifications (user_id, post_id) VALUES (cur_user_id, @new_post_id);

        -- Fetch the next user_id
        FETCH user_cursor INTO cur_user_id;
    END WHILE;

    -- Close the cursor
    CLOSE user_cursor;
END$$

DELIMITER ;



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


