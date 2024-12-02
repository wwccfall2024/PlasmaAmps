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
  name VARCHAR(30) NOT NULL,
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

CREATE VIEW character_items AS
SELECT DISTINCT
    c.character_id,
    c.name AS character_name,
    i.name AS item_name,
    i.armor,
    i.damage
FROM
    characters c
LEFT JOIN
    inventory inv ON c.character_id = inv.character_id
LEFT JOIN
    equipped eq ON c.character_id = eq.character_id
LEFT JOIN
    items i ON i.item_id = COALESCE(inv.item_id, eq.item_id);


CREATE VIEW team_items AS
SELECT DISTINCT
    t.team_id,
    t.name AS team_name,
    i.name AS item_name,
    i.armor,
    i.damage
FROM
    teams t
INNER JOIN
    team_members tm ON t.team_id = tm.team_id
INNER JOIN
    inventory inv ON tm.character_id = inv.character_id
INNER JOIN
    equipped eq ON tm.character_id = eq.character_id
INNER JOIN
    items i ON i.item_id = COALESCE(inv.item_id, eq.item_id);




DELIMITER $$

CREATE FUNCTION armor_total(character_id INT) 
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE total_armor INT DEFAULT 0;

    -- Sum the armor from the character's stats (if applicable)
    SELECT armor INTO total_armor
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

CREATE PROCEDURE equip(in _inventory_id INT)
BEGIN
    -- Declare variables to store character_id and item_id
    DECLARE _character_id INT;
    DECLARE _item_id INT;

    -- Get the character_id and item_id from the inventory table
    SELECT character_id, item_id
    INTO _character_id, _item_id
    FROM inventory
    WHERE inventory_id = _inventory_id;

    -- Remove the item from the inventory table
    DELETE FROM inventory WHERE inventory_id = _inventory_id;

    -- Add the item to the equipped table
    INSERT INTO equipped (character_id, item_id)
    VALUES (_character_id, _item_id);
END $$

CREATE PROCEDURE unequip(in _equipped_id INT)
BEGIN
    -- Declare variables to store character_id and item_id
    DECLARE _character_id INT;
    DECLARE _item_id INT;

    -- Get the character_id and item_id from the equipped table
    SELECT character_id, item_id
    INTO _character_id, _item_id
    FROM equipped
    WHERE equipped_id = _equipped_id
    LIMIT 1;

    -- Remove the item from the equipped table
    DELETE FROM equipped WHERE equipped_id = _equipped_id;

    -- Add the item back to the inventory table
    INSERT INTO inventory (character_id, item_id)
    VALUES (_character_id, _item_id);
END $$
  
CREATE PROCEDURE set_winners(IN team_id INT)
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE character_id INT;
    DECLARE cursor_winners CURSOR FOR
        SELECT tm.character_id
        FROM team_members tm
        JOIN character_stats cs ON tm.character_id = cs.character_id
        WHERE tm.team_id = team_id AND cs.health > 0;

 -- Declare a handler to handle the end of the cursor
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    -- Empty the winners table
    DELETE FROM winners;

    -- Open the cursor
    OPEN cursor_winners;

    -- Loop through each result
    read_loop: LOOP
        FETCH cursor_winners INTO character_id;
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Insert each winner into the winners table
        INSERT INTO winners (character_id, name)
        SELECT DISTINCT c.character_id, c.name
        FROM characters c
        WHERE c.character_id = character_id
        ON DUPLICATE KEY UPDATE name = VALUES(name);
    END LOOP;

    -- Close the cursor
    CLOSE cursor_winners;
END $$

DELIMITER ;
