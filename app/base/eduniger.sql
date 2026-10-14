-- phpMyAdmin SQL Dump
-- version 5.1.1deb5ubuntu1
-- https://www.phpmyadmin.net/
--
-- Hôte : localhost:3306
-- Généré le : mer. 07 oct. 2026 à 15:20
-- Version du serveur : 8.0.43-0ubuntu0.22.04.2
-- Version de PHP : 8.1.2-1ubuntu2.22

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de données : `eduniger`
--

-- --------------------------------------------------------

--
-- Structure de la table `Agent`
--

CREATE TABLE `Agent` (
  `idAgent` varchar(256) NOT NULL,
  `name` varchar(256) NOT NULL,
  `firstName` varchar(256) NOT NULL,
  `isAdmin` tinyint DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `AgentAccount`
--

CREATE TABLE `AgentAccount` (
  `idAgentAccount` int NOT NULL,
  `idAgent` varchar(256) NOT NULL,
  `email` varchar(256) NOT NULL,
  `password` varchar(1000) NOT NULL,
  `profile` varchar(256) DEFAULT NULL,
  `isAdmin` tinyint DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `Audio`
--

CREATE TABLE `Audio` (
  `idAudio` int NOT NULL,
  `idBook` varchar(256) DEFAULT NULL,
  `audio` varchar(256) NOT NULL,
  `title` varchar(256) NOT NULL,
  `size` varchar(1000) DEFAULT NULL,
  `maxTime` varchar(1000) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `Author`
--

CREATE TABLE `Author` (
  `idAuthor` int NOT NULL,
  `name` varchar(256) NOT NULL,
  `firstName` varchar(256) NOT NULL,
  `profile` varchar(256) DEFAULT NULL,
  `level` tinyint DEFAULT '0',
  `profession` varchar(1000) DEFAULT 'AUTEUR EDUNIGER',
  `biography` text,
  `call` varchar(1000) DEFAULT NULL,
  `email` varchar(1000) DEFAULT NULL,
  `whatsapp` varchar(1000) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déchargement des données de la table `Author`
--

INSERT INTO `Author` (`idAuthor`, `name`, `firstName`, `profile`, `level`, `profession`, `biography`, `call`, `email`, `whatsapp`) VALUES
(2, 'OBEECS', 'OBEECS', 'author_6b745ffd-f9d8-4f4d-ad7f-8c28f32f30b7.png', 0, 'Structures', NULL, NULL, NULL, NULL),
(3, 'Abdoul Kader', 'Bachir', 'author_ac153d60-d3ae-459a-9e68-38a5cc98a648.png', 3, 'PDG EDUNIGER', NULL, NULL, NULL, NULL),
(4, 'Hamidou Ridouane', 'Aboubacar', 'user.png', 0, NULL, NULL, NULL, NULL, NULL);

-- --------------------------------------------------------

--
-- Structure de la table `Book`
--

CREATE TABLE `Book` (
  `idBook` varchar(256) NOT NULL,
  `title` varchar(256) NOT NULL,
  `description` text,
  `idAuthor` int NOT NULL,
  `blanket` varchar(1000) NOT NULL,
  `electronic` varchar(1000) DEFAULT NULL,
  `isPhysic` tinyint DEFAULT '0',
  `isAudio` tinyint DEFAULT '0',
  `available` int DEFAULT '0',
  `numberLike` int DEFAULT '0',
  `numberNoLike` int DEFAULT '0',
  `numberView` int DEFAULT '0',
  `numberComment` int DEFAULT '0',
  `numberSubscribe` int DEFAULT '0',
  `size` varchar(1000) DEFAULT NULL,
  `nbrPage` varchar(1000) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déchargement des données de la table `Book`
--

INSERT INTO `Book` (`idBook`, `title`, `description`, `idAuthor`, `blanket`, `electronic`, `isPhysic`, `isAudio`, `available`, `numberLike`, `numberNoLike`, `numberView`, `numberComment`, `numberSubscribe`, `size`, `nbrPage`, `created_at`, `updated_at`) VALUES
('TD0001', 'Epreuve de Français 2020', 'Epreuve de Français 2020', 2, 'TD0001_1788961716.jpg', 'TD0001_1788961716.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '1.23', '3', '2026-09-09 12:48:36', '2026-09-09 12:50:20'),
('TD0002', 'Epreuve d\'Anglais 2020', 'Epreuve d\'Anglais 2020', 2, 'TD0002_1788962105.jpg', 'TD0002_1788962105.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '0.7', '2', '2026-09-09 12:55:05', '2026-09-09 12:55:05'),
('TD0003', 'Epreuve d\'Arabe 2020', 'Epreuve d\'Arabe 2020', 2, 'TD0003_1788962268.jpg', 'TD0003_1788962268.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '0.31', '2', '2026-09-09 12:57:48', '2026-09-09 12:57:48'),
('TD0004', 'Epreuve d\'Histoire-Géographie 2020', 'Epreuve d\'Histoire-Géographie 2020', 2, 'TD0004_1788962505.jpg', 'TD0004_1788962505.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '0.81', '2', '2026-09-09 13:01:45', '2026-09-09 13:01:45'),
('TD0005', 'Epreuve de Philosophie 2020', 'Epreuve de Philosophie 2020', 2, 'TD0005_1788962686.jpg', 'TD0005_1788962686.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '0.32', '1', '2026-09-09 13:04:46', '2026-09-09 13:04:46'),
('TD0006', 'Epreuve de Mathématiques 2020', 'Epreuve de Mathématiques 2020', 2, 'TD0006_1788963056.jpg', 'TD0006_1788963056.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '0.68', '3', '2026-09-09 13:10:56', '2026-09-09 13:10:56'),
('TD0007', 'Epreuve de Sciences Physiques 2020', 'Epreuve de Sciences Physiques 2020', 2, 'TD0007_1788963301.jpg', 'TD0007_1788963301.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '0.9', '2', '2026-09-09 13:15:01', '2026-09-09 13:15:01'),
('TD0008', 'Epreuve de Sciences de la Vie et de la Terre 2020', 'Epreuve de Sciences de la Vie et de la Terre 2020', 2, 'TD0008_1788963398.jpg', 'TD0008_1788963398.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '0.82', '2', '2026-09-09 13:16:38', '2026-09-09 13:16:38'),
('TD0009', 'Epreuve de Dessin-Couture 2020', 'Epreuve de Dessin-Couture 2020', 2, 'TD0009_1788963562.jpg', 'TD0009_1788963562.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '0.18', '1', '2026-09-09 13:19:22', '2026-09-09 13:19:22'),
('TEST0001', 'TEST01', NULL, 2, 'TEST0001_1788783227.jpg', 'TEST0001_1788783227.pdf', 0, 0, 1, 0, 0, 0, 0, 0, '0.09', '11', '2026-09-07 11:13:48', '2026-09-07 11:13:48');

-- --------------------------------------------------------

--
-- Structure de la table `BookCategory`
--

CREATE TABLE `BookCategory` (
  `idBook` varchar(256) NOT NULL,
  `idCategory` int NOT NULL,
  `date` datetime NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déchargement des données de la table `BookCategory`
--

INSERT INTO `BookCategory` (`idBook`, `idCategory`, `date`, `created_at`, `updated_at`) VALUES
('TD0001', 3, '2026-09-09 13:50:20', '2026-09-09 12:50:20', '2026-09-09 12:50:20'),
('TD0002', 4, '2026-09-09 13:55:05', '2026-09-09 12:55:05', '2026-09-09 12:55:05'),
('TD0003', 5, '2026-09-09 13:57:48', '2026-09-09 12:57:48', '2026-09-09 12:57:48'),
('TD0004', 6, '2026-09-09 14:01:45', '2026-09-09 13:01:45', '2026-09-09 13:01:45'),
('TD0004', 7, '2026-09-09 14:01:45', '2026-09-09 13:01:45', '2026-09-09 13:01:45'),
('TD0005', 8, '2026-09-09 14:04:46', '2026-09-09 13:04:46', '2026-09-09 13:04:46'),
('TD0006', 2, '2026-09-09 14:10:56', '2026-09-09 13:10:56', '2026-09-09 13:10:56'),
('TD0007', 9, '2026-09-09 14:15:01', '2026-09-09 13:15:01', '2026-09-09 13:15:01'),
('TD0008', 9, '2026-09-09 14:16:38', '2026-09-09 13:16:38', '2026-09-09 13:16:38'),
('TD0009', 10, '2026-09-09 14:19:22', '2026-09-09 13:19:22', '2026-09-09 13:19:22'),
('TEST0001', 2, '2026-09-07 12:13:48', '2026-09-07 11:13:48', '2026-09-07 11:13:48');

-- --------------------------------------------------------

--
-- Structure de la table `cache`
--

CREATE TABLE `cache` (
  `key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `value` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `expiration` int NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `cache_locks`
--

CREATE TABLE `cache_locks` (
  `key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `owner` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `expiration` int NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `Category`
--

CREATE TABLE `Category` (
  `idCategory` int NOT NULL,
  `title` varchar(256) DEFAULT NULL,
  `blanket` text,
  `date` datetime NOT NULL,
  `numberSubscribe` int DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déchargement des données de la table `Category`
--

INSERT INTO `Category` (`idCategory`, `title`, `blanket`, `date`, `numberSubscribe`) VALUES
(2, 'Mathématiques', 'category_a2ab4d19-152c-4fe7-9aa1-31eefb803117.png', '2026-09-07 12:01:42', 0),
(3, 'Français', 'category_392a17c4-d729-4943-bb6f-fb46fd9ae986.png', '2026-09-09 13:47:19', 0),
(4, 'Anglais', 'category_e7ca0f1c-918e-45d3-8bfb-617e8f67006e.png', '2026-09-09 13:52:58', 0),
(5, 'Arabe', 'category_0dee22d5-a8fe-4a54-9ce6-6b790b29beac.png', '2026-09-09 13:56:25', 0),
(6, 'Histoire', 'category_1c860d26-cb0b-40e7-851c-0ddd9bc37525.png', '2026-09-09 13:59:29', 0),
(7, 'Géographie', 'category_59ea9db5-d97a-4274-a325-588ee707956f.png', '2026-09-09 14:00:20', 0),
(8, 'Philosophie', 'category_98f4c8c2-d36e-4228-aaa9-a2126a502958.png', '2026-09-09 14:03:16', 0),
(9, 'Sciences', 'category_98854a36-a383-4d9c-978b-af51a2d42653.png', '2026-09-09 14:13:31', 0),
(10, 'Couture', 'category_4dd9e889-e27b-4f53-93ae-65e9d9a2caf0.png', '2026-09-09 14:18:12', 0);

--
-- Déclencheurs `Category`
--
DELIMITER $$
CREATE TRIGGER `AFTER_INSERT_CATEGORY` AFTER INSERT ON `Category` FOR EACH ROW BEGIN
    DECLARE tmp VARCHAR(256);
    DECLARE student VARCHAR(256);
    DECLARE category INT;
    SET category = NEW.idCategory;

    SELECT idNumber INTO student FROM SubscribeCategory WHERE idCategory=category ORDER BY idNumber DESC LIMIT 1;
    REPEAT
        INSERT INTO `Notification` VALUES (NULL,student,NOW(),"Un nouveau livre de cette catgorie est mainteant disponiple.",0,4,category,0);
        SET tmp=student;
        SET student=NULL;
        SELECT idNumber INTO student FROM SubscribeCategory WHERE idCategory=category AND idNumber<tmp ORDER BY idNumber DESC LIMIT 1;
        UNTIL student IS NULL
    END REPEAT;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `EdunaConversation`
--

CREATE TABLE `EdunaConversation` (
  `idConversation` int NOT NULL,
  `idUser` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `session_id` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_message` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `assistant_response` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `book_context` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `EdunaFavorite`
--

CREATE TABLE `EdunaFavorite` (
  `idFavorite` int NOT NULL,
  `idConversation` int NOT NULL,
  `idUser` varchar(256) NOT NULL,
  `note` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `EdunaFeedback`
--

CREATE TABLE `EdunaFeedback` (
  `idFeedback` int NOT NULL,
  `idConversation` int NOT NULL,
  `idUser` varchar(256) NOT NULL,
  `rating` tinyint NOT NULL COMMENT '1-5 étoiles',
  `comment` text,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `EdunaPDF`
--

CREATE TABLE `EdunaPDF` (
  `idPDF` int NOT NULL,
  `idBook` varchar(256) DEFAULT NULL,
  `filename` varchar(500) NOT NULL,
  `filepath` varchar(1000) NOT NULL,
  `title` varchar(500) DEFAULT NULL,
  `content_text` longtext,
  `content_embedding` longtext,
  `page_count` int DEFAULT NULL,
  `file_size` int DEFAULT NULL,
  `last_accessed` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `EdunaPDFQuery`
--

CREATE TABLE `EdunaPDFQuery` (
  `idQuery` int NOT NULL,
  `idUser` varchar(256) NOT NULL,
  `idPDF` int DEFAULT NULL,
  `idBook` varchar(256) DEFAULT NULL,
  `query` text NOT NULL,
  `response` text NOT NULL,
  `relevant_pages` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `EdunaSession`
--

CREATE TABLE `EdunaSession` (
  `idSession` int NOT NULL,
  `idUser` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `session_id` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `last_interaction` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `message_count` int DEFAULT '1',
  `context` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `preferences` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `failed_jobs`
--

CREATE TABLE `failed_jobs` (
  `id` bigint UNSIGNED NOT NULL,
  `uuid` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `connection` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `queue` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `payload` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `exception` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `failed_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `help_requests`
--

CREATE TABLE `help_requests` (
  `id` bigint UNSIGNED NOT NULL,
  `user_id` bigint UNSIGNED NOT NULL,
  `structure_id` int NOT NULL,
  `type` enum('problem','bug','improvement','service') COLLATE utf8mb4_unicode_ci NOT NULL,
  `title` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `message` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('open','in_progress','resolved','closed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open',
  `priority` enum('low','medium','high') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'medium',
  `admin_response` text COLLATE utf8mb4_unicode_ci,
  `responded_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `invitation_logs`
--

CREATE TABLE `invitation_logs` (
  `id` bigint UNSIGNED NOT NULL,
  `agent_id` bigint UNSIGNED NOT NULL,
  `generated_code` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `expires_at` timestamp NOT NULL,
  `generated_by` bigint UNSIGNED DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `invitation_logs`
--

INSERT INTO `invitation_logs` (`id`, `agent_id`, `generated_code`, `expires_at`, `generated_by`, `created_at`, `updated_at`) VALUES
(1, 3, '32X6-4842', '2026-09-08 10:59:21', NULL, '2026-09-07 10:59:21', '2026-09-07 10:59:21'),
(2, 4, 'A68F-8841', '2026-09-08 11:12:17', NULL, '2026-09-07 11:12:17', '2026-09-07 11:12:17'),
(3, 5, 'I63H-6363', '2026-09-10 12:40:52', NULL, '2026-09-09 12:40:52', '2026-09-09 12:40:52');

-- --------------------------------------------------------

--
-- Structure de la table `jobs`
--

CREATE TABLE `jobs` (
  `id` bigint UNSIGNED NOT NULL,
  `queue` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `payload` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `attempts` tinyint UNSIGNED NOT NULL,
  `reserved_at` int UNSIGNED DEFAULT NULL,
  `available_at` int UNSIGNED NOT NULL,
  `created_at` int UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `job_batches`
--

CREATE TABLE `job_batches` (
  `id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `total_jobs` int NOT NULL,
  `pending_jobs` int NOT NULL,
  `failed_jobs` int NOT NULL,
  `failed_job_ids` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `options` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `cancelled_at` int DEFAULT NULL,
  `created_at` int NOT NULL,
  `finished_at` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `Like`
--

CREATE TABLE `Like` (
  `idNumber` varchar(256) NOT NULL,
  `idBook` varchar(256) NOT NULL,
  `date` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déclencheurs `Like`
--
DELIMITER $$
CREATE TRIGGER `AFTER_DELETE_LIKE` AFTER DELETE ON `Like` FOR EACH ROW BEGIN
    UPDATE `Book` SET numberLike=numberLike-1 WHERE `idBook`=OLD.idBook;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `AFTER_INSERT_LIKE` AFTER INSERT ON `Like` FOR EACH ROW BEGIN
    UPDATE `Book` SET numberLike=numberLike+1 WHERE `idBook`=NEW.idBook;
    DELETE FROM `NoLike` WHERE idNumber=NEW.idNumber AND `idBook`=NEW.idBook;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `Loand`
--

CREATE TABLE `Loand` (
  `idLoand` int NOT NULL,
  `idReservation` int NOT NULL,
  `idBook` varchar(256) NOT NULL,
  `idAgentGiver` varchar(256) NOT NULL,
  `idAgentRecover` varchar(256) DEFAULT NULL,
  `dateLoand` datetime NOT NULL,
  `realReturnDate` datetime NOT NULL,
  `actualReturnDate` datetime DEFAULT NULL,
  `closing` tinyint DEFAULT '0',
  `view` tinyint DEFAULT '0',
  `idStruct` int NOT NULL,
  `idUser` varchar(100) NOT NULL,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `migrations`
--

CREATE TABLE `migrations` (
  `id` int UNSIGNED NOT NULL,
  `migration` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `batch` int NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `migrations`
--

INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES
(1, '0001_01_01_000000_create_users_table', 1),
(2, '0001_01_01_000001_create_cache_table', 1),
(3, '0001_01_01_000002_create_jobs_table', 1),
(4, '2019_12_14_000001_create_personal_access_tokens_table', 2),
(5, '2025_06_09_085959_create_personal_access_tokens_table', 3),
(6, '2025_06_09_105834_create_users_table', 4),
(7, '2026_04_01_091455_create_help_requests_table', 5),
(8, '2026_09_14_112145_make_category_blanket_nullable', 5);

-- --------------------------------------------------------

--
-- Structure de la table `NoLike`
--

CREATE TABLE `NoLike` (
  `idNumber` varchar(256) NOT NULL,
  `idBook` varchar(256) NOT NULL,
  `date` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déclencheurs `NoLike`
--
DELIMITER $$
CREATE TRIGGER `AFTER_DELETE_NOLIKE` AFTER DELETE ON `NoLike` FOR EACH ROW BEGIN
    UPDATE `Book` SET numberNoLike=numberNoLike-1 WHERE `idBook`=OLD.idBook;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `AFTER_INSERT_NOLIKE` AFTER INSERT ON `NoLike` FOR EACH ROW BEGIN
    UPDATE `Book` SET numberNoLike=numberNoLike+1 WHERE `idBook`=NEW.idBook;
    DELETE FROM `Like` WHERE idNumber=NEW.idNumber AND `idBook`=NEW.idBook;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `Notification`
--

CREATE TABLE `Notification` (
  `idNotification` int NOT NULL,
  `idNumber` varchar(256) DEFAULT NULL,
  `date` datetime NOT NULL,
  `message` text NOT NULL,
  `state` tinyint DEFAULT '0',
  `type` int DEFAULT '0',
  `reference` int DEFAULT '0',
  `view` tinyint DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déchargement des données de la table `Notification`
--

INSERT INTO `Notification` (`idNotification`, `idNumber`, `date`, `message`, `state`, `type`, `reference`, `view`) VALUES
(1, NULL, '2026-09-07 12:39:33', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 1, 0),
(2, NULL, '2026-09-07 13:01:42', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 2, 0),
(3, NULL, '2026-09-09 14:47:19', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 3, 0),
(4, NULL, '2026-09-09 14:52:58', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 4, 0),
(5, NULL, '2026-09-09 14:56:25', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 5, 0),
(6, NULL, '2026-09-09 14:59:29', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 6, 0),
(7, NULL, '2026-09-09 15:00:20', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 7, 0),
(8, NULL, '2026-09-09 15:03:16', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 8, 0),
(9, NULL, '2026-09-09 15:13:31', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 9, 0),
(10, NULL, '2026-09-09 15:18:12', 'Un nouveau livre de cette catgorie est mainteant disponiple.', 0, 4, 10, 0);

-- --------------------------------------------------------

--
-- Structure de la table `password_reset_tokens`
--

CREATE TABLE `password_reset_tokens` (
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `token` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `personal_access_tokens`
--

CREATE TABLE `personal_access_tokens` (
  `id` bigint UNSIGNED NOT NULL,
  `tokenable_type` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `tokenable_id` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `token` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `abilities` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `last_used_at` timestamp NULL DEFAULT NULL,
  `expires_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `personal_access_tokens`
--

INSERT INTO `personal_access_tokens` (`id`, `tokenable_type`, `tokenable_id`, `name`, `token`, `abilities`, `last_used_at`, `expires_at`, `created_at`, `updated_at`) VALUES
(4, 'App\\Models\\StructAgent', '1', 'authToken', '4f4cea495fe114d2fbe0492f39766460c670c037ee667dd91647cfaf1e485934', '[\"*\"]', '2026-09-07 10:35:23', NULL, '2026-09-07 10:35:09', '2026-09-07 10:35:23'),
(5, 'App\\Models\\StructAgent', '1', 'authToken', '5f3392a8dbebff761414af26e3c9d984bd14115c66eef168c6b16c043559790b', '[\"*\"]', '2026-09-07 10:39:33', NULL, '2026-09-07 10:39:31', '2026-09-07 10:39:33'),
(6, 'App\\Models\\StructAgent', '1', 'authToken', 'a9d7ef3aaff0297bae6797e7d90d63bfb7611ad4d6e886f810592d1c968eff9d', '[\"*\"]', '2026-09-07 10:41:11', NULL, '2026-09-07 10:41:10', '2026-09-07 10:41:11'),
(7, 'App\\Models\\StructAgent', '1', 'authToken', 'e5384838fcaff8d47495dde4bb596012924b1832d8d3ea3af87ea5da2e2d84ed', '[\"*\"]', '2026-09-07 10:44:06', NULL, '2026-09-07 10:44:05', '2026-09-07 10:44:06'),
(8, 'App\\Models\\StructAgent', '1', 'authToken', 'b8ac9dc62bc9c31ffd44795ddc45f8bfef683408c0abe601dc262ee1b993dc92', '[\"*\"]', '2026-09-07 10:45:15', NULL, '2026-09-07 10:45:14', '2026-09-07 10:45:15'),
(9, 'App\\Models\\StructAgent', '1', 'authToken', '5701f5c4184cf531b3b34ab64112f24749045139b927d7ff40b658fa03fce959', '[\"*\"]', '2026-09-07 10:49:53', NULL, '2026-09-07 10:49:41', '2026-09-07 10:49:53'),
(10, 'App\\Models\\StructAgent', '2', 'authToken', '7241211bc84529c634c258e278755b49aef49bcd19fbfbeb87de194e6eb42a3b', '[\"*\"]', '2026-09-07 10:49:42', NULL, '2026-09-07 10:49:41', '2026-09-07 10:49:42'),
(11, 'App\\Models\\StructAgent', '3', 'authToken', '737766646db5eebbcdf2ca316b8ac73ebde4ddaea312abcdd55810bb3509a449', '[\"*\"]', '2026-09-07 11:06:43', NULL, '2026-09-07 10:59:45', '2026-09-07 11:06:43'),
(14, 'App\\Models\\StructAgent', '4', 'authToken', 'e788adb7cfc8b9e9674697d5ed318c46017da344bd7dd3a84e661ec77c514435', '[\"*\"]', '2026-09-07 12:03:09', NULL, '2026-09-07 11:12:38', '2026-09-07 12:03:09'),
(15, 'App\\Models\\StructAgent', '1', 'authToken', 'fe135f588c9993e8843ca811511d4591c1f67f51b9c8104ac11f60827733c4e1', '[\"*\"]', '2026-09-07 11:15:10', NULL, '2026-09-07 11:15:09', '2026-09-07 11:15:10'),
(16, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', 'd53c4adc2cad805b6fc5466f6cc58be1eadd85303496f8457f93850ea80ff97b', '[\"*\"]', NULL, NULL, '2026-09-07 13:29:39', '2026-09-07 13:29:39'),
(17, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '8b37cea953dc9dbb99d2f4a535a3e6f66680b7fa8f1d75fb7f7748ef3271755f', '[\"*\"]', NULL, NULL, '2026-09-07 13:29:53', '2026-09-07 13:29:53'),
(18, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '92c71801059bfba46e9e67955d20658654aa16acd3a6110b0e297a56bd677916', '[\"*\"]', NULL, NULL, '2026-09-07 13:41:43', '2026-09-07 13:41:43'),
(19, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', 'f8be48ab455148e745e0c3bd927ff9ac0d1193960cf01a66e699fed5c119ab48', '[\"*\"]', '2026-09-07 14:16:37', NULL, '2026-09-07 14:16:37', '2026-09-07 14:16:37'),
(20, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', 'ec4f682448f2b52b48a9c59ee1a7fb58a18fdbf9a7b4824488404d757bc269f8', '[\"*\"]', '2026-09-07 14:17:12', NULL, '2026-09-07 14:17:11', '2026-09-07 14:17:12'),
(21, 'App\\Models\\StructAgent', '4', 'authToken', '9211325fa915229815d3027cb670da5ffa514b5bfb5ab2194a95ac96664bb182', '[\"*\"]', '2026-09-07 14:19:06', NULL, '2026-09-07 14:18:58', '2026-09-07 14:19:06'),
(22, 'App\\Models\\StructAgent', '4', 'authToken', 'e92e979584d563e127bbaddba29dcbc16d3259013fec3bb0884e548c2342e6a5', '[\"*\"]', '2026-09-08 13:11:33', NULL, '2026-09-07 18:55:17', '2026-09-08 13:11:33'),
(23, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '4f0317194e7b353acbaacc47b75a80947770d34e6f0ccdcf91640658ee39c5e5', '[\"*\"]', '2026-09-07 19:03:18', NULL, '2026-09-07 19:03:17', '2026-09-07 19:03:18'),
(24, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '0919e22923afa1fcec34c42f46956b54632e6d55038e43c1b333a5726a495e61', '[\"*\"]', '2026-09-07 19:07:35', NULL, '2026-09-07 19:07:35', '2026-09-07 19:07:35'),
(25, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '6e1c86cf572432edbf7e581e6e841fd20ffd2ffc07ddf321c6bf9106b9e0e7c1', '[\"*\"]', '2026-09-07 19:16:00', NULL, '2026-09-07 19:16:00', '2026-09-07 19:16:00'),
(26, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '45aea61284105534c725de956439efb4d475dd70f39d61c18f2d3c72be99c242', '[\"*\"]', '2026-09-07 19:24:14', NULL, '2026-09-07 19:24:13', '2026-09-07 19:24:14'),
(27, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '11481c2607c2a113c50d3503ada9d08ff6056ff19665286ed69bf2b727aa7c4c', '[\"*\"]', '2026-09-08 08:14:38', NULL, '2026-09-07 19:33:36', '2026-09-08 08:14:38'),
(28, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', 'da5aa282facd8fcfe91dc43249468e6d51f784f8bdefd9b40ce77f3e6981d172', '[\"*\"]', '2026-09-14 12:43:39', NULL, '2026-09-08 08:15:22', '2026-09-14 12:43:39'),
(31, 'App\\Models\\StructAgent', '5', 'authToken', 'ed4eb6d117960aaa739bdc6a37566c5f6ed67ff5d61746e5816aef4cbcae29fc', '[\"*\"]', '2026-09-09 13:26:57', NULL, '2026-09-09 12:41:12', '2026-09-09 13:26:57'),
(32, 'App\\Models\\StructAgent', '4', 'authToken', '8d3317b3e14c140ed2f50c718c2618ff524d0ca42d698b2d8db454246faeb007', '[\"*\"]', '2026-09-14 12:27:36', NULL, '2026-09-14 12:27:19', '2026-09-14 12:27:36'),
(33, 'App\\Models\\StructAgent', '4', 'authToken', '029ce83f4fb4ce82e90a647db3cad92632dd998049adbc4529b70017eaa6b176', '[\"*\"]', '2026-09-14 12:31:45', NULL, '2026-09-14 12:31:31', '2026-09-14 12:31:45'),
(34, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '025c33e551742656c7c044904c3008bf0ef821a47d031dac119d1f63fc043166', '[\"*\"]', '2026-09-14 12:59:21', NULL, '2026-09-14 12:45:50', '2026-09-14 12:59:21'),
(35, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', 'a826a55ba4892ca6c5967bf438f81cbd444e33373346975edce31d9d99b002ca', '[\"*\"]', '2026-09-14 13:34:41', NULL, '2026-09-14 13:30:01', '2026-09-14 13:34:41'),
(36, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '1654f9e94ed9e8f18920f28d180b777f9369c23d453160a7de5a691bd7786647', '[\"*\"]', '2026-09-14 13:38:53', NULL, '2026-09-14 13:37:31', '2026-09-14 13:38:53'),
(37, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '9ce53a4b2816aa6a141217f889e885ad0afd4a62069196e20a90cd34ab86503f', '[\"*\"]', '2026-09-14 13:46:14', NULL, '2026-09-14 13:46:13', '2026-09-14 13:46:14'),
(38, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', 'cfbaecbad35a1a8516e2110ac604786907baa74641d8a0909d1ca27d1c5539bb', '[\"*\"]', '2026-09-14 13:52:49', NULL, '2026-09-14 13:52:47', '2026-09-14 13:52:49'),
(39, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '21d972b43d5256222b17ffcc59c27b06680f08b5eb6abd67256c6b1df286499c', '[\"*\"]', '2026-09-14 14:51:17', NULL, '2026-09-14 14:05:34', '2026-09-14 14:51:17'),
(40, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '220b16caba24f98ae299ad442935b0e8e2f3da0694e4915242f74ac1353ccba6', '[\"*\"]', '2026-09-15 08:44:31', NULL, '2026-09-14 14:53:46', '2026-09-15 08:44:31'),
(42, 'App\\Models\\StructAgent', '5', 'authToken', '59757f119fcd8fda7e50c0250da648e1ba7f844f1cc9b104054cc75b8dc48c5f', '[\"*\"]', '2026-09-14 15:26:39', NULL, '2026-09-14 15:26:33', '2026-09-14 15:26:39'),
(43, 'App\\Models\\StructAgent', '4', 'authToken', '33c96d350492306db60550b9d9e4786b4136508b667eb605f966f9043e8519e4', '[\"*\"]', '2026-09-15 08:46:51', NULL, '2026-09-15 08:46:21', '2026-09-15 08:46:51'),
(44, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '869ea874ad33211971be5e74bb8402b712cd853cbc96c88cf5a20d05b0ca345a', '[\"*\"]', '2026-10-04 07:45:03', NULL, '2026-09-18 07:51:31', '2026-10-04 07:45:03'),
(45, 'App\\Models\\User', '63d49fa8-55b6-4985-8a5c-390e16e0467f', 'auth_token', '36d20e326765371303f44e6db50f0c5981ca325026f3293134ba2ecf33795ea3', '[\"*\"]', '2026-10-07 13:19:45', NULL, '2026-10-06 11:05:21', '2026-10-07 13:19:45');

-- --------------------------------------------------------

--
-- Structure de la table `RefreshToken`
--

CREATE TABLE `RefreshToken` (
  `id` int NOT NULL,
  `idUser` varchar(256) NOT NULL,
  `tokenHash` char(64) NOT NULL,
  `familyId` char(36) NOT NULL,
  `createdAt` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expiresAt` datetime NOT NULL,
  `revokedAt` datetime DEFAULT NULL,
  `replacedByHash` char(64) DEFAULT NULL,
  `userAgent` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `Reservation`
--

CREATE TABLE `Reservation` (
  `idReservation` int NOT NULL,
  `idNumber` varchar(256) NOT NULL,
  `idBook` varchar(256) DEFAULT NULL,
  `idStruct` int NOT NULL,
  `date` datetime DEFAULT NULL,
  `numberOfDay` tinyint DEFAULT '0',
  `expireDate` datetime DEFAULT NULL,
  `deliveryDate` datetime DEFAULT NULL,
  `state` tinyint DEFAULT '1',
  `treat` tinyint DEFAULT '1',
  `view` tinyint DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `Sanction`
--

CREATE TABLE `Sanction` (
  `idSanction` int NOT NULL,
  `idNumber` varchar(256) DEFAULT NULL,
  `description` text NOT NULL,
  `date` datetime NOT NULL,
  `state` tinyint DEFAULT '1'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `sessions`
--

CREATE TABLE `sessions` (
  `id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` bigint UNSIGNED DEFAULT NULL,
  `ip_address` varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `user_agent` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `payload` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `last_activity` int NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `StructBook`
--

CREATE TABLE `StructBook` (
  `idStruct` int NOT NULL,
  `idBook` varchar(256) NOT NULL,
  `date` datetime NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déchargement des données de la table `StructBook`
--

INSERT INTO `StructBook` (`idStruct`, `idBook`, `date`, `created_at`, `updated_at`) VALUES
(1, 'TEST0001', '2026-09-07 12:13:48', '2026-09-07 11:13:48', '2026-09-07 11:13:48'),
(2, 'TD0001', '2026-09-09 13:48:36', '2026-09-09 12:48:36', '2026-09-09 12:48:36'),
(2, 'TD0002', '2026-09-09 13:55:05', '2026-09-09 12:55:05', '2026-09-09 12:55:05'),
(2, 'TD0003', '2026-09-09 13:57:48', '2026-09-09 12:57:48', '2026-09-09 12:57:48'),
(2, 'TD0004', '2026-09-09 14:01:45', '2026-09-09 13:01:45', '2026-09-09 13:01:45'),
(2, 'TD0005', '2026-09-09 14:04:46', '2026-09-09 13:04:46', '2026-09-09 13:04:46'),
(2, 'TD0006', '2026-09-09 14:10:56', '2026-09-09 13:10:56', '2026-09-09 13:10:56'),
(2, 'TD0007', '2026-09-09 14:15:01', '2026-09-09 13:15:01', '2026-09-09 13:15:01'),
(2, 'TD0008', '2026-09-09 14:16:38', '2026-09-09 13:16:38', '2026-09-09 13:16:38'),
(2, 'TD0009', '2026-09-09 14:19:22', '2026-09-09 13:19:22', '2026-09-09 13:19:22');

-- --------------------------------------------------------

--
-- Structure de la table `Structure`
--

CREATE TABLE `Structure` (
  `id` int NOT NULL,
  `nameStruct` varchar(256) NOT NULL,
  `description` varchar(10000) DEFAULT NULL,
  `logo` varchar(256) DEFAULT NULL,
  `banner` varchar(256) DEFAULT 'banner.png',
  `author` varchar(256) DEFAULT NULL,
  `adhererNumber` int DEFAULT '0',
  `bookNumber` int DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `location` varchar(255) DEFAULT NULL,
  `storageLimit` bigint UNSIGNED DEFAULT '16106100000'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déchargement des données de la table `Structure`
--

INSERT INTO `Structure` (`id`, `nameStruct`, `description`, `logo`, `banner`, `author`, `adhererNumber`, `bookNumber`, `created_at`, `updated_at`, `location`, `storageLimit`) VALUES
(1, 'Aika', 'Aika', 'logo_1788783086.png', 'banner_1788783086.png', NULL, 1, 0, NULL, '2026-09-09 09:26:56', 'Niger', 10000000000000),
(2, 'Kit TD', 'Retrouvez au même endroit tous les documents essentiels pour préparer efficacement la Terminale D : cours, TD, exercices, annales, corrigés et ressources complémentaires.', 'logo_1788961198.png', 'banner_1788961198.png', NULL, 0, 0, NULL, '2026-09-09 12:39:58', 'Niger', 3000000000000000000);

-- --------------------------------------------------------

--
-- Structure de la table `StructureNotifications`
--

CREATE TABLE `StructureNotifications` (
  `id` bigint UNSIGNED NOT NULL,
  `idStruct` int DEFAULT NULL,
  `title` varchar(255) NOT NULL,
  `message` text NOT NULL,
  `type` enum('info','warning','success','system') DEFAULT 'info',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- --------------------------------------------------------

--
-- Structure de la table `StructUser`
--

CREATE TABLE `StructUser` (
  `idStruct` int NOT NULL,
  `idUser` varchar(256) NOT NULL,
  `date` datetime NOT NULL,
  `isAdmin` tinyint DEFAULT '0',
  `registerNumber` varchar(10000) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déchargement des données de la table `StructUser`
--

INSERT INTO `StructUser` (`idStruct`, `idUser`, `date`, `isAdmin`, `registerNumber`, `created_at`, `updated_at`) VALUES
(1, '63d49fa8-55b6-4985-8a5c-390e16e0467f', '2026-09-09 10:26:56', 0, NULL, '2026-09-09 09:26:56', '2026-09-09 09:26:56'),
(2, '63d49fa8-55b6-4985-8a5c-390e16e0467f', '2026-09-09 15:24:39', 0, '94961793', '2026-09-09 14:25:10', '2026-09-09 14:25:10');

-- --------------------------------------------------------

--
-- Structure de la table `struct_agent`
--

CREATE TABLE `struct_agent` (
  `id` int NOT NULL,
  `name` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `phoneNumber` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `role` tinyint NOT NULL DEFAULT '0',
  `idStruct` int DEFAULT NULL,
  `isAuthorizedToCreateAccount` tinyint(1) NOT NULL DEFAULT '0',
  `invitationCode` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `codeExpiresAt` datetime DEFAULT NULL,
  `password` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `struct_agent`
--

INSERT INTO `struct_agent` (`id`, `name`, `email`, `phoneNumber`, `role`, `idStruct`, `isAuthorizedToCreateAccount`, `invitationCode`, `codeExpiresAt`, `password`, `created_at`, `updated_at`) VALUES
(1, 'Super Administrateur', 'contact@naniger.com', NULL, 2, NULL, 1, NULL, NULL, '$2y$12$o0TP7lISlwchn3WMySV20.1dcsT4KsWxfpfWk.xOQdsWHaqWP/Yxm', '2026-09-07 10:03:31', '2026-09-07 10:03:31'),
(4, 'Bachir Abdoul Kader', 'kader@naniger.com', '+22794961793', 1, 1, 1, 'A68F-8841', '2026-09-08 12:12:17', '$2y$12$vSAVgpw59k2qN415QTmrXuU/o2/2yJlB6rLByY9HLZ5hoFIp07mjS', '2026-09-07 11:12:17', '2026-09-07 11:12:17'),
(5, 'Bachir Abdoul Kader', 'kittd@naniger.com', '11111111', 1, 2, 1, 'I63H-6363', '2026-09-10 13:40:52', '$2y$12$FdjM9idc.9Bp9PcqNXO.d.I6yhiYn/VTf53glm2hdK/FG5PLh9J36', '2026-09-09 12:40:52', '2026-09-09 12:40:52');

-- --------------------------------------------------------

--
-- Structure de la table `Student`
--

CREATE TABLE `Student` (
  `idNumber` varchar(256) NOT NULL,
  `name` varchar(256) NOT NULL,
  `firstName` varchar(256) NOT NULL,
  `section` varchar(256) DEFAULT NULL,
  `department` varchar(256) DEFAULT NULL,
  `isDelegue` tinyint DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `SubscribeBook`
--

CREATE TABLE `SubscribeBook` (
  `idNumber` varchar(256) NOT NULL,
  `idBook` varchar(256) NOT NULL,
  `date` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déclencheurs `SubscribeBook`
--
DELIMITER $$
CREATE TRIGGER `AFTER_DELETE_SUBSCRIBEBOOK` AFTER DELETE ON `SubscribeBook` FOR EACH ROW BEGIN
    UPDATE `Book` SET numberSubscribe=numberSubscribe-1 WHERE `idBook`=OLD.idBook;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `AFTER_INSERT_SUBSCRIBEBOOK` AFTER INSERT ON `SubscribeBook` FOR EACH ROW BEGIN
    UPDATE `Book` SET numberSubscribe=numberSubscribe+1 WHERE `idBook`=NEW.idBook;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `SubscribeCategory`
--

CREATE TABLE `SubscribeCategory` (
  `idNumber` varchar(256) NOT NULL,
  `idCategory` int NOT NULL,
  `date` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déclencheurs `SubscribeCategory`
--
DELIMITER $$
CREATE TRIGGER `AFTER_DELETE_SUBSCRIBECATEGORY` AFTER DELETE ON `SubscribeCategory` FOR EACH ROW BEGIN
    UPDATE `Category` SET numberSubscribe=numberSubscribe-1 WHERE `idCategory`=OLD.idCategory;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `AFTER_INSERT_SUBSCRIBECATEGORY` AFTER INSERT ON `SubscribeCategory` FOR EACH ROW BEGIN
    UPDATE `Category` SET numberSubscribe=numberSubscribe+1 WHERE `idCategory`=NEW.idCategory;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `User`
--

CREATE TABLE `User` (
  `idUser` varchar(256) NOT NULL,
  `name` varchar(256) NOT NULL,
  `firstName` varchar(256) NOT NULL,
  `email` varchar(256) NOT NULL,
  `password` varchar(1000) NOT NULL,
  `profile` varchar(256) DEFAULT 'user.png',
  `profession` tinyint DEFAULT '0',
  `isAdmin` tinyint DEFAULT '0',
  `phoneNumber` varchar(50) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `fcm_token` varchar(10000) DEFAULT NULL,
  `role` varchar(20) NOT NULL DEFAULT 'USER',
  `failed_login_attempts` int NOT NULL DEFAULT '0',
  `locked_until` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déchargement des données de la table `User`
--

INSERT INTO `User` (`idUser`, `name`, `firstName`, `email`, `password`, `profile`, `profession`, `isAdmin`, `phoneNumber`, `created_at`, `updated_at`, `fcm_token`, `role`, `failed_login_attempts`, `locked_until`) VALUES
('63d49fa8-55b6-4985-8a5c-390e16e0467f', 'Abdoul Kader', 'Bachir', 'bachirabdoulkader62331@gmail.com', '$2y$12$xTXa6P0YTx8VwBtedKrAduKYIUnrqMyIguQYjnq8GqmwLj29k/lGC', 'user.png', 4, 0, '94961793', '2026-09-07 13:29:39', '2026-10-06 12:17:05', 'ceF3iMXISxCkmtzcu5NOUS:APA91bHFbecWmSGDwyvFHVv-4tmFTsQTBdXkIcrUfks3TEU46mmFZAcnD4Zn-f5MzGARsun5-fTEloOmLWNXwEy4dCPAfXUzc0IKmoOhxxbKUiJbl1Zf8G8', 'USER', 0, NULL);

-- --------------------------------------------------------

--
-- Structure de la table `UserNotificationRead`
--

CREATE TABLE `UserNotificationRead` (
  `id` bigint UNSIGNED NOT NULL,
  `user_id` int NOT NULL,
  `notification_id` bigint UNSIGNED NOT NULL,
  `read_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- --------------------------------------------------------

--
-- Structure de la table `users`
--

CREATE TABLE `users` (
  `id` bigint UNSIGNED NOT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `email_verified_at` timestamp NULL DEFAULT NULL,
  `password` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `remember_token` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Structure de la table `Version`
--

CREATE TABLE `Version` (
  `idVersion` varchar(256) NOT NULL,
  `date` datetime NOT NULL,
  `description` text
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- --------------------------------------------------------

--
-- Structure de la table `View`
--

CREATE TABLE `View` (
  `idNumber` varchar(256) NOT NULL,
  `idBook` varchar(256) NOT NULL,
  `date` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

--
-- Déclencheurs `View`
--
DELIMITER $$
CREATE TRIGGER `AFTER_DELETE_VIEW` AFTER DELETE ON `View` FOR EACH ROW BEGIN
    UPDATE `Book` SET numberView=numberView-1 WHERE `idBook`=OLD.idBook;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `AFTER_INSERT_VIEW` AFTER INSERT ON `View` FOR EACH ROW BEGIN
    UPDATE `Book` SET numberView=numberView+1 WHERE `idBook`=NEW.idBook;
END
$$
DELIMITER ;

--
-- Index pour les tables déchargées
--

--
-- Index pour la table `Agent`
--
ALTER TABLE `Agent`
  ADD PRIMARY KEY (`idAgent`);

--
-- Index pour la table `AgentAccount`
--
ALTER TABLE `AgentAccount`
  ADD PRIMARY KEY (`idAgentAccount`),
  ADD UNIQUE KEY `email` (`email`),
  ADD KEY `FK_AGENT_AGENTENTACCOUNT` (`idAgent`);

--
-- Index pour la table `Audio`
--
ALTER TABLE `Audio`
  ADD PRIMARY KEY (`idAudio`);

--
-- Index pour la table `Author`
--
ALTER TABLE `Author`
  ADD PRIMARY KEY (`idAuthor`);

--
-- Index pour la table `Book`
--
ALTER TABLE `Book`
  ADD PRIMARY KEY (`idBook`),
  ADD KEY `FK_AUTHOR_BOOK` (`idAuthor`);

--
-- Index pour la table `BookCategory`
--
ALTER TABLE `BookCategory`
  ADD PRIMARY KEY (`idBook`,`idCategory`),
  ADD KEY `FK_CATEGORY_BOOKCATEGORY` (`idCategory`);

--
-- Index pour la table `cache`
--
ALTER TABLE `cache`
  ADD PRIMARY KEY (`key`);

--
-- Index pour la table `cache_locks`
--
ALTER TABLE `cache_locks`
  ADD PRIMARY KEY (`key`);

--
-- Index pour la table `Category`
--
ALTER TABLE `Category`
  ADD PRIMARY KEY (`idCategory`);

--
-- Index pour la table `EdunaConversation`
--
ALTER TABLE `EdunaConversation`
  ADD PRIMARY KEY (`idConversation`);

--
-- Index pour la table `EdunaSession`
--
ALTER TABLE `EdunaSession`
  ADD PRIMARY KEY (`idSession`);

--
-- Index pour la table `failed_jobs`
--
ALTER TABLE `failed_jobs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `failed_jobs_uuid_unique` (`uuid`);

--
-- Index pour la table `help_requests`
--
ALTER TABLE `help_requests`
  ADD PRIMARY KEY (`id`),
  ADD KEY `help_requests_user_id_foreign` (`user_id`),
  ADD KEY `help_requests_structure_id_foreign` (`structure_id`);

--
-- Index pour la table `invitation_logs`
--
ALTER TABLE `invitation_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_invitation_agent_id` (`agent_id`),
  ADD KEY `idx_invitation_generated_code` (`generated_code`),
  ADD KEY `idx_invitation_generated_by` (`generated_by`);

--
-- Index pour la table `jobs`
--
ALTER TABLE `jobs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `jobs_queue_index` (`queue`);

--
-- Index pour la table `job_batches`
--
ALTER TABLE `job_batches`
  ADD PRIMARY KEY (`id`);

--
-- Index pour la table `Like`
--
ALTER TABLE `Like`
  ADD PRIMARY KEY (`idNumber`,`idBook`),
  ADD KEY `FK_BOOK_LIKE` (`idBook`);

--
-- Index pour la table `Loand`
--
ALTER TABLE `Loand`
  ADD PRIMARY KEY (`idLoand`),
  ADD KEY `FK_RESERVATION_BORROWING` (`idReservation`),
  ADD KEY `FK_STRUCTURE_LOAND` (`idStruct`),
  ADD KEY `FK_USER_LOAND` (`idUser`),
  ADD KEY `idx_loand_agent_giver` (`idAgentGiver`),
  ADD KEY `idx_loand_agent_recover` (`idAgentRecover`);

--
-- Index pour la table `migrations`
--
ALTER TABLE `migrations`
  ADD PRIMARY KEY (`id`);

--
-- Index pour la table `NoLike`
--
ALTER TABLE `NoLike`
  ADD PRIMARY KEY (`idNumber`,`idBook`),
  ADD KEY `FK_BOOK_NOLIKE` (`idBook`);

--
-- Index pour la table `Notification`
--
ALTER TABLE `Notification`
  ADD PRIMARY KEY (`idNotification`),
  ADD KEY `FK_STUDENT_NOTIFICATION` (`idNumber`);

--
-- Index pour la table `password_reset_tokens`
--
ALTER TABLE `password_reset_tokens`
  ADD PRIMARY KEY (`email`);

--
-- Index pour la table `personal_access_tokens`
--
ALTER TABLE `personal_access_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `personal_access_tokens_token_unique` (`token`),
  ADD KEY `personal_access_tokens_tokenable_type_tokenable_id_index` (`tokenable_type`,`tokenable_id`);

--
-- Index pour la table `RefreshToken`
--
ALTER TABLE `RefreshToken`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_token_hash` (`tokenHash`),
  ADD KEY `idx_user` (`idUser`),
  ADD KEY `idx_family` (`familyId`);

--
-- Index pour la table `Reservation`
--
ALTER TABLE `Reservation`
  ADD PRIMARY KEY (`idReservation`),
  ADD KEY `FK_STUDENT_RESERVATION` (`idNumber`),
  ADD KEY `FK_BOOK_RESERVATION` (`idBook`),
  ADD KEY `idx_reservation_idstruct` (`idStruct`);

--
-- Index pour la table `Sanction`
--
ALTER TABLE `Sanction`
  ADD PRIMARY KEY (`idSanction`),
  ADD KEY `FK_STUDENT_SANCTION` (`idNumber`);

--
-- Index pour la table `sessions`
--
ALTER TABLE `sessions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `sessions_user_id_index` (`user_id`),
  ADD KEY `sessions_last_activity_index` (`last_activity`);

--
-- Index pour la table `StructBook`
--
ALTER TABLE `StructBook`
  ADD PRIMARY KEY (`idStruct`,`idBook`),
  ADD KEY `FK_Book_STRUCTBOOK` (`idBook`);

--
-- Index pour la table `Structure`
--
ALTER TABLE `Structure`
  ADD PRIMARY KEY (`id`);

--
-- Index pour la table `StructureNotifications`
--
ALTER TABLE `StructureNotifications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `structurenotifications_idstruct_foreign` (`idStruct`);

--
-- Index pour la table `StructUser`
--
ALTER TABLE `StructUser`
  ADD PRIMARY KEY (`idStruct`,`idUser`),
  ADD KEY `FK_USER_STRUCTUSER` (`idUser`);

--
-- Index pour la table `struct_agent`
--
ALTER TABLE `struct_agent`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`),
  ADD KEY `idStruct` (`idStruct`);

--
-- Index pour la table `Student`
--
ALTER TABLE `Student`
  ADD PRIMARY KEY (`idNumber`);

--
-- Index pour la table `SubscribeBook`
--
ALTER TABLE `SubscribeBook`
  ADD PRIMARY KEY (`idNumber`,`idBook`),
  ADD KEY `FK_BOOK_SUSCRIBEBOOK` (`idBook`);

--
-- Index pour la table `SubscribeCategory`
--
ALTER TABLE `SubscribeCategory`
  ADD PRIMARY KEY (`idNumber`,`idCategory`),
  ADD KEY `FK_CATEGORY_SUSCRIBECATEGORY` (`idCategory`);

--
-- Index pour la table `User`
--
ALTER TABLE `User`
  ADD PRIMARY KEY (`idUser`),
  ADD UNIQUE KEY `email` (`email`),
  ADD UNIQUE KEY `phoneNumber` (`phoneNumber`);

--
-- Index pour la table `UserNotificationRead`
--
ALTER TABLE `UserNotificationRead`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `usernotificationread_unique` (`user_id`,`notification_id`),
  ADD KEY `usernotificationread_notificationid_foreign` (`notification_id`);

--
-- Index pour la table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `users_email_unique` (`email`);

--
-- Index pour la table `Version`
--
ALTER TABLE `Version`
  ADD PRIMARY KEY (`idVersion`);

--
-- Index pour la table `View`
--
ALTER TABLE `View`
  ADD PRIMARY KEY (`idNumber`,`idBook`),
  ADD KEY `FK_BOOK_VIEW` (`idBook`);

--
-- AUTO_INCREMENT pour les tables déchargées
--

--
-- AUTO_INCREMENT pour la table `AgentAccount`
--
ALTER TABLE `AgentAccount`
  MODIFY `idAgentAccount` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `Audio`
--
ALTER TABLE `Audio`
  MODIFY `idAudio` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `Author`
--
ALTER TABLE `Author`
  MODIFY `idAuthor` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT pour la table `Category`
--
ALTER TABLE `Category`
  MODIFY `idCategory` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT pour la table `EdunaConversation`
--
ALTER TABLE `EdunaConversation`
  MODIFY `idConversation` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `EdunaSession`
--
ALTER TABLE `EdunaSession`
  MODIFY `idSession` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `failed_jobs`
--
ALTER TABLE `failed_jobs`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `help_requests`
--
ALTER TABLE `help_requests`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `invitation_logs`
--
ALTER TABLE `invitation_logs`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT pour la table `jobs`
--
ALTER TABLE `jobs`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `Loand`
--
ALTER TABLE `Loand`
  MODIFY `idLoand` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `migrations`
--
ALTER TABLE `migrations`
  MODIFY `id` int UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT pour la table `Notification`
--
ALTER TABLE `Notification`
  MODIFY `idNotification` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT pour la table `personal_access_tokens`
--
ALTER TABLE `personal_access_tokens`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=46;

--
-- AUTO_INCREMENT pour la table `RefreshToken`
--
ALTER TABLE `RefreshToken`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `Reservation`
--
ALTER TABLE `Reservation`
  MODIFY `idReservation` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `Sanction`
--
ALTER TABLE `Sanction`
  MODIFY `idSanction` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `Structure`
--
ALTER TABLE `Structure`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT pour la table `StructureNotifications`
--
ALTER TABLE `StructureNotifications`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `struct_agent`
--
ALTER TABLE `struct_agent`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT pour la table `UserNotificationRead`
--
ALTER TABLE `UserNotificationRead`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `users`
--
ALTER TABLE `users`
  MODIFY `id` bigint UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Contraintes pour les tables déchargées
--

--
-- Contraintes pour la table `AgentAccount`
--
ALTER TABLE `AgentAccount`
  ADD CONSTRAINT `FK_AGENT_AGENTENTACCOUNT` FOREIGN KEY (`idAgent`) REFERENCES `Agent` (`idAgent`) ON DELETE CASCADE;

--
-- Contraintes pour la table `Book`
--
ALTER TABLE `Book`
  ADD CONSTRAINT `FK_AUTHOR_BOOK` FOREIGN KEY (`idAuthor`) REFERENCES `Author` (`idAuthor`) ON DELETE CASCADE;

--
-- Contraintes pour la table `BookCategory`
--
ALTER TABLE `BookCategory`
  ADD CONSTRAINT `FK_BOOK_BOOKCATEGORY` FOREIGN KEY (`idBook`) REFERENCES `Book` (`idBook`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_CATEGORY_BOOKCATEGORY` FOREIGN KEY (`idCategory`) REFERENCES `Category` (`idCategory`) ON DELETE CASCADE;

--
-- Contraintes pour la table `help_requests`
--
ALTER TABLE `help_requests`
  ADD CONSTRAINT `help_requests_structure_id_foreign` FOREIGN KEY (`structure_id`) REFERENCES `Structure` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `help_requests_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `Like`
--
ALTER TABLE `Like`
  ADD CONSTRAINT `FK_BOOK_LIKE` FOREIGN KEY (`idBook`) REFERENCES `Book` (`idBook`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_USER_LIKE` FOREIGN KEY (`idNumber`) REFERENCES `User` (`idUser`) ON DELETE CASCADE;

--
-- Contraintes pour la table `Loand`
--
ALTER TABLE `Loand`
  ADD CONSTRAINT `FK_RESERVATION_BORROWING` FOREIGN KEY (`idReservation`) REFERENCES `Reservation` (`idReservation`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_STRUCTURE_LOAND` FOREIGN KEY (`idStruct`) REFERENCES `Structure` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_USER_LOAND` FOREIGN KEY (`idUser`) REFERENCES `User` (`idUser`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Contraintes pour la table `NoLike`
--
ALTER TABLE `NoLike`
  ADD CONSTRAINT `FK_BOOK_NOLIKE` FOREIGN KEY (`idBook`) REFERENCES `Book` (`idBook`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_USER_NOLIKE` FOREIGN KEY (`idNumber`) REFERENCES `User` (`idUser`) ON DELETE CASCADE;

--
-- Contraintes pour la table `Notification`
--
ALTER TABLE `Notification`
  ADD CONSTRAINT `FK_STUDENT_NOTIFICATION` FOREIGN KEY (`idNumber`) REFERENCES `Student` (`idNumber`) ON DELETE CASCADE;

--
-- Contraintes pour la table `RefreshToken`
--
ALTER TABLE `RefreshToken`
  ADD CONSTRAINT `fk_refresh_token_user` FOREIGN KEY (`idUser`) REFERENCES `User` (`idUser`) ON DELETE CASCADE;

--
-- Contraintes pour la table `Reservation`
--
ALTER TABLE `Reservation`
  ADD CONSTRAINT `FK_BOOK_RESERVATION` FOREIGN KEY (`idBook`) REFERENCES `Book` (`idBook`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_RESERVATION_STRUCTURE` FOREIGN KEY (`idStruct`) REFERENCES `Structure` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_USER_RESERVATION` FOREIGN KEY (`idNumber`) REFERENCES `User` (`idUser`) ON DELETE CASCADE;

--
-- Contraintes pour la table `Sanction`
--
ALTER TABLE `Sanction`
  ADD CONSTRAINT `FK_STUDENT_SANCTION` FOREIGN KEY (`idNumber`) REFERENCES `Student` (`idNumber`) ON DELETE CASCADE;

--
-- Contraintes pour la table `StructBook`
--
ALTER TABLE `StructBook`
  ADD CONSTRAINT `FK_Book_STRUCTBOOK` FOREIGN KEY (`idBook`) REFERENCES `Book` (`idBook`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_STRUCTURE_STRUCTBOOK` FOREIGN KEY (`idStruct`) REFERENCES `Structure` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `StructureNotifications`
--
ALTER TABLE `StructureNotifications`
  ADD CONSTRAINT `structurenotifications_idstruct_foreign` FOREIGN KEY (`idStruct`) REFERENCES `Structure` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `StructUser`
--
ALTER TABLE `StructUser`
  ADD CONSTRAINT `FK_STRUCTURE_STRUCTUSER` FOREIGN KEY (`idStruct`) REFERENCES `Structure` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_USER_STRUCTUSER` FOREIGN KEY (`idUser`) REFERENCES `User` (`idUser`) ON DELETE CASCADE;

--
-- Contraintes pour la table `struct_agent`
--
ALTER TABLE `struct_agent`
  ADD CONSTRAINT `struct_agent_ibfk_1` FOREIGN KEY (`idStruct`) REFERENCES `Structure` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `SubscribeBook`
--
ALTER TABLE `SubscribeBook`
  ADD CONSTRAINT `FK_BOOK_SUSCRIBEBOOK` FOREIGN KEY (`idBook`) REFERENCES `Book` (`idBook`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_USER_SUSCRIBEBOOK` FOREIGN KEY (`idNumber`) REFERENCES `User` (`idUser`) ON DELETE CASCADE;

--
-- Contraintes pour la table `SubscribeCategory`
--
ALTER TABLE `SubscribeCategory`
  ADD CONSTRAINT `FK_CATEGORY_SUSCRIBECATEGORY` FOREIGN KEY (`idCategory`) REFERENCES `Category` (`idCategory`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_STUDENT_SUSCRIBECATEGORY` FOREIGN KEY (`idNumber`) REFERENCES `Student` (`idNumber`) ON DELETE CASCADE;

--
-- Contraintes pour la table `UserNotificationRead`
--
ALTER TABLE `UserNotificationRead`
  ADD CONSTRAINT `usernotificationread_notificationid_foreign` FOREIGN KEY (`notification_id`) REFERENCES `StructureNotifications` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `usernotificationread_userid_foreign` FOREIGN KEY (`user_id`) REFERENCES `struct_agent` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `View`
--
ALTER TABLE `View`
  ADD CONSTRAINT `FK_BOOK_VIEW` FOREIGN KEY (`idBook`) REFERENCES `Book` (`idBook`) ON DELETE CASCADE,
  ADD CONSTRAINT `FK_USER_VIEW` FOREIGN KEY (`idNumber`) REFERENCES `User` (`idUser`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
