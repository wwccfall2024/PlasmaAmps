-- Create your tables, views, functions and procedures here!
CREATE SCHEMA destruction;
USE destruction;

CREATE TABLE players (
  player_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
  first_name VARCHAR(30) NOT NULL,
  last_name VARCHAR(30) NOT NULL,
  email VARCHAR(50) NOT NULL
);

CREATE TABLE characters (
  character_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
  player_id INT UNSIGNED NULL,
  name VARCHAR(30) NOT NULL,
  level INT UNSIGNED NOT NULL,
  FOREIGN KEY (player_id) REFERENCES players(player_id) 
    ON DELETE SET NULL 
    ON UPDATE CASCADE
);

CREATE TABLE winners (
  character_id INT UNSIGNED PRIMARY KEY,
  name VARCHAR(30) NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(character_id)
    ON DELETE CASCADE 
    ON UPDATE CASCADE
);

CREATE TABLE character_stats (
  character_id INT UNSIGNED PRIMARY KEY,
  health INT UNSIGNED NOT NULL,
  armor INT UNSIGNED NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(character_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE teams (
  team_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
  name VARCHAR(30)
);

CREATE TABLE team_members (
  team_member_id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  team_id INT UNSIGNED NOT NULL,
  character_id INT UNSIGNED NOT NULL,
  FOREIGN KEY (team_id) REFERENCES teams(team_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  FOREIGN KEY (character_id) REFERENCES characters(character_id)
    ON DELETE CASCADE 
    ON UPDATE CASCADE
);

CREATE TABLE items (
  item_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
  name VARCHAR(30),
  armor INT UNSIGNED NOT NULL,
  damage INT UNSIGNED NOT NULL
);

CREATE TABLE inventory (
  inventory_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
  character_id INT UNSIGNED NULL,
  item_id INT UNSIGNED NULL,
  FOREIGN KEY (character_id) REFERENCES characters(character_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  FOREIGN KEY (item_id) REFERENCES items(item_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE equipped (
  equipped_id INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
  character_id INT UNSIGNED NOT NULL,
  item_id INT UNSIGNED NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(character_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  FOREIGN KEY (item_id) REFERENCES items(item_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

DELIMITER $$

CREATE FUNCTION armor_total(character_id INT) 
RETURNS INT
BEGIN
    DECLARE total_armor INT DEFAULT 0;

    -- Sum the armor from the character's stats (if applicable)
    SELECT stats_armor INTO total_armor
    FROM character_stats
    WHERE character_id = character_id;

    -- Add the armor from the equipped items
    SELECT SUM(i.armor) INTO total_armor
    FROM equipped e
    JOIN items i ON e.item_id = i.item_id
    WHERE e.character_id = character_id;

    RETURN total_armor;
END $$

CREATE PROCEDURE attack(
    IN id_of_character_being_attacked INT,
    IN id_of_equipped_item_used_for_attack INT
)
BEGIN
    DECLARE damage INT;
    DECLARE armor INT;
    DECLARE health INT;
    
    -- Get the damage of the equipped item
    SELECT damage INTO damage
    FROM items
    WHERE item_id = id_of_equipped_item_used_for_attack;
    
    -- Get the total armor of the attacked character
    SET armor = armor_total(id_of_character_being_attacked);
    
    -- Get the current health of the attacked character
    SELECT health INTO health
    FROM character_stats
    WHERE character_id = id_of_character_being_attacked;

    -- Calculate the net damage after subtracting armor
    SET damage = GREATEST(0, damage - armor);  -- Prevent negative damage

    -- If damage is positive, apply the damage to the character's health
    IF damage > 0 THEN
        SET health = health - damage;
        
        -- Update health in the character stats table
        UPDATE character_stats
        SET health = health
        WHERE character_id = id_of_character_being_attacked;

        -- If the character's health reaches 0 or below, they die
        IF health <= 0 THEN
            -- Delete the character and all related records
            DELETE FROM character_stats WHERE character_id = id_of_character_being_attacked;
            DELETE FROM equipped WHERE character_id = id_of_character_being_attacked;
            DELETE FROM inventory WHERE character_id = id_of_character_being_attacked;
            DELETE FROM team_members WHERE character_id = id_of_character_being_attacked;
        END IF;
    END IF;
END $$

CREATE PROCEDURE equip(IN inventory_id INT)
BEGIN
    DECLARE character_id INT;
    DECLARE item_id INT;

    -- Get the character_id and item_id from the inventory
    SELECT character_id, item_id INTO character_id, item_id
    FROM inventory
    WHERE inventory_id = inventory_id;

    -- Add the item to the equipped table
    INSERT INTO equipped (character_id, item_id)
    VALUES (character_id, item_id);

    -- Remove the item from the inventory table
    DELETE FROM inventory
    WHERE inventory_id = inventory_id;
END $$

CREATE PROCEDURE unequip(IN equipped_id INT)
BEGIN
    DECLARE character_id INT;
    DECLARE item_id INT;

    -- Get the character_id and item_id from the equipped table
    SELECT character_id, item_id INTO character_id, item_id
    FROM equipped
    WHERE equipped_id = equipped_id;

    -- Remove the item from the equipped table
    DELETE FROM equipped
    WHERE equipped_id = equipped_id;

    -- Add the item back to the inventory table
    INSERT INTO inventory (character_id, item_id)
    VALUES (character_id, item_id);
END $$

CREATE PROCEDURE set_winners(IN team_id INT)
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE character_id INT;
    DECLARE cursor CURSOR FOR
        SELECT tm.character_id
        FROM team_members tm
        JOIN character_stats cs ON tm.character_id = cs.character_id
        WHERE tm.team_id = team_id AND cs.health > 0;

    -- Open the cursor for the team
    OPEN cursor;

    -- Empty the winners table
    DELETE FROM winners;

    -- Add the winning team members to the winners table
    read_loop: LOOP
        FETCH cursor INTO character_id;
        IF done THEN
            LEAVE read_loop;
        END IF;

        INSERT INTO winners (team_id, character_id)
        VALUES (team_id, character_id);
    END LOOP;

    -- Close the cursor
    CLOSE cursor;
END $$

DELIMITER ;
