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
  armor INT NOT NULL,
  damage INT NOT NULL
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
INNER JOIN (
    SELECT character_id, item_id
    FROM inventory
    UNION ALL
    SELECT character_id, item_id
    FROM equipped
) all_items ON c.character_id = all_items.character_id
INNER JOIN items i ON all_items.item_id = i.item_id
  ORDER BY c.character_id, i.name;


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

CREATE FUNCTION armor_total(char_id INT UNSIGNED) 
RETURNS INT
READS SQL DATA
BEGIN
    -- Variables to store intermediate results
    DECLARE char_armor INT;
    DECLARE equipped_armor INT;
    DECLARE total_armor INT UNSIGNED;

    -- Get the base armor from character stats (if available)
    SELECT armor INTO char_armor
    FROM character_stats
    WHERE character_id = char_id;

    -- Sum the armor values of equipped items (if any)
    SELECT SUM(i.armor) INTO equipped_armor
    FROM equipped e
    INNER JOIN items i ON e.item_id = i.item_id
    WHERE e.character_id = char_id;

    -- Add base stats and equipped armor
    SET total_armor = char_armor + equipped_armor;

    RETURN total_armor;
END $$

CREATE PROCEDURE attack(
    IN target_character_id INT,
    IN equipped_item_id INT
)
BEGIN
    DECLARE equipped_item_damage INT;
    DECLARE target_character_armor INT;
    DECLARE target_character_health INT;

    -- Get the damage of the equipped item
    SELECT damage INTO equipped_item_damage
    FROM items
    WHERE item_id = equipped_item_id;

    -- Get the total armor of the attacked character
    SET target_character_armor = armor_total(target_character_id);

    -- Get the current health of the attacked character
    SELECT health INTO target_character_health
    FROM character_stats
    WHERE character_id = target_character_id;

    -- Calculate the net damage after subtracting armor
    SET equipped_item_damage = GREATEST(0, equipped_item_damage - target_character_armor); -- Prevent negative damage

    -- If damage is positive, apply the damage to the character's health
    IF equipped_item_damage > 0 THEN
        SET target_character_health = target_character_health - equipped_item_damage;

        -- Update health in the character stats table
        UPDATE character_stats
        SET health = target_character_health
        WHERE character_id = target_character_id;

        -- If the character's health reaches 0 or below, they die
        IF target_character_health <= 0 THEN
            -- Delete the character and all related records
            DELETE FROM character_stats WHERE character_id = target_character_id;
            DELETE FROM equipped WHERE character_id = target_character_id;
            DELETE FROM inventory WHERE character_id = target_character_id;
            DELETE FROM team_members WHERE character_id = target_character_id;
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
