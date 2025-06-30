'use strict'
angular.module("beamng.apps").directive("floodleaderboard", [function () {
	return {
		templateUrl: '/ui/modules/apps/floodleaderboard/app.html',
		replace: true,
		link: function ($scope, element, attrs) {
			
			// Initialize scope variables
			$scope.leaderboardData = [];
			$scope.dailyRecords = [];
			$scope.weeklyRecords = [];
			$scope.roundTime = "00:00";
			$scope.activeTab = "current";
			$scope.isAppFocused = false;
			$scope.compactHeaderHidden = false;

			// Focus management
			$scope.setAppFocus = function(focused) {
				$scope.isAppFocused = focused;
				if (!$scope.$$phase) {
					$scope.$apply();
				}
			};

			// Tab management
			$scope.setActiveTab = function(tab) {
				$scope.activeTab = tab;
			};

			// Helper functions
			$scope.getRankMedal = function(rank) {
				switch(rank) {
					case 1: return "🥇";
					case 2: return "🥈";
					case 3: return "🥉";
					default: return "";
				}
			};

			$scope.getTopThree = function() {
				return $scope.leaderboardData.slice(0, 3);
			};

			$scope.getPlayerCount = function() {
				switch($scope.activeTab) {
					case 'current': return $scope.leaderboardData.length;
					case 'daily': return $scope.dailyRecords.length;
					case 'weekly': return $scope.weeklyRecords.length;
					default: return 0;
				}
			};

			$scope.getSubtitleText = function() {
				switch($scope.activeTab) {
					case 'current': return 'Current Round Progress';
					case 'daily': return 'Today\'s Best Records';
					case 'weekly': return 'This Week\'s Champions';
					default: return 'Leaderboard';
				}
			};

			$scope.formatDateTime = function(timestamp) {
				const date = new Date(timestamp);
				const now = new Date();
				const diffMs = now - date;
				const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
				const diffDays = Math.floor(diffHours / 24);

				if (diffDays === 0) {
					if (diffHours === 0) {
						const diffMins = Math.floor(diffMs / (1000 * 60));
						return diffMins <= 0 ? 'Just now' : `${diffMins}m ago`;
					}
					return `${diffHours}h ago`;
				} else if (diffDays < 7) {
					return `${diffDays}d ago`;
				} else {
					return date.toLocaleDateString('en-US', { 
						month: 'short', 
						day: 'numeric',
						hour: '2-digit',
						minute: '2-digit'
					});
				}
			};

			// Static test data for current round
			function initializeCurrentData() {
				$scope.leaderboardData = [
					{
						rank: 1,
						name: "SpeedDemon",
						vehicle: "ETK 800-Series",
						distance: 1247,
						power: 245,
						currentDistance: 1247,
						totalDistance: 2000,
						progressPercent: 62.35,
						isCurrentPlayer: false
					},
					{
						rank: 2,
						name: "WaterWalker",
						vehicle: "Gavril Roamer",
						distance: 1156,
						power: 189,
						currentDistance: 1156,
						totalDistance: 2000,
						progressPercent: 57.8,
						isCurrentPlayer: true
					},
					{
						rank: 3,
						name: "FloodMaster",
						vehicle: "Hirochi SBR4",
						distance: 1089,
						power: 298,
						currentDistance: 1089,
						totalDistance: 2000,
						progressPercent: 54.45,
						isCurrentPlayer: false
					},
					{
						rank: 4,
						name: "AquaRacer",
						vehicle: "Cherrier FCV",
						distance: 967,
						power: 156,
						currentDistance: 967,
						totalDistance: 2000,
						progressPercent: 48.35,
						isCurrentPlayer: false
					},
					{
						rank: 5,
						name: "TidalWave",
						vehicle: "Ibishu Covet",
						distance: 834,
						power: 123,
						currentDistance: 834,
						totalDistance: 2000,
						progressPercent: 41.7,
						isCurrentPlayer: false
					},
					{
						rank: 6,
						name: "DeepDiver",
						vehicle: "Gavril D-Series",
						distance: 721,
						power: 267,
						currentDistance: 721,
						totalDistance: 2000,
						progressPercent: 36.05,
						isCurrentPlayer: false
					}
				];
			}

			// Static test data for daily records
			function initializeDailyData() {
				const now = new Date();
				const maxDistance = 3000; // Max possible distance for progress calculation
				$scope.dailyRecords = [
					{
						rank: 1,
						name: "RecordBreaker",
						distance: 2847,
						power: 278,
						timestamp: new Date(now - 2 * 60 * 60 * 1000), // 2 hours ago
						floodSpeed: 0.8,
						maxDistance: maxDistance,
						progressPercent: (2847 / maxDistance * 100).toFixed(1)
					},
					{
						rank: 2,
						name: "SpeedDemon",
						distance: 2634,
						power: 245,
						timestamp: new Date(now - 5 * 60 * 60 * 1000), // 5 hours ago
						floodSpeed: 0.9,
						maxDistance: maxDistance,
						progressPercent: (2634 / maxDistance * 100).toFixed(1)
					},
					{
						rank: 3,
						name: "FloodMaster",
						distance: 2456,
						power: 298,
						timestamp: new Date(now - 7 * 60 * 60 * 1000), // 7 hours ago
						floodSpeed: 0.7,
						maxDistance: maxDistance,
						progressPercent: (2456 / maxDistance * 100).toFixed(1)
					},
					{
						rank: 4,
						name: "AquaKing",
						distance: 2298,
						power: 212,
						timestamp: new Date(now - 9 * 60 * 60 * 1000), // 9 hours ago
						floodSpeed: 1.0,
						maxDistance: maxDistance,
						progressPercent: (2298 / maxDistance * 100).toFixed(1)
					},
					{
						rank: 5,
						name: "WaterWalker",
						distance: 2156,
						power: 189,
						timestamp: new Date(now - 11 * 60 * 60 * 1000), // 11 hours ago
						floodSpeed: 0.6,
						maxDistance: maxDistance,
						progressPercent: (2156 / maxDistance * 100).toFixed(1)
					}
				];
			}

			// Static test data for weekly records
			function initializeWeeklyData() {
				const now = new Date();
				const maxDistance = 3500; // Higher max for weekly records
				$scope.weeklyRecords = [
					{
						rank: 1,
						name: "LegendaryFlooder",
						distance: 3247,
						power: 325,
						timestamp: new Date(now - 2 * 24 * 60 * 60 * 1000), // 2 days ago
						floodSpeed: 1.2,
						maxDistance: maxDistance,
						progressPercent: (3247 / maxDistance * 100).toFixed(1)
					},
					{
						rank: 2,
						name: "RecordBreaker",
						distance: 3089,
						power: 278,
						timestamp: new Date(now - 1 * 24 * 60 * 60 * 1000), // 1 day ago
						floodSpeed: 1.1,
						maxDistance: maxDistance,
						progressPercent: (3089 / maxDistance * 100).toFixed(1)
					},
					{
						rank: 3,
						name: "MasterOfWaves",
						distance: 2934,
						power: 289,
						timestamp: new Date(now - 3 * 24 * 60 * 60 * 1000), // 3 days ago
						floodSpeed: 0.9,
						maxDistance: maxDistance,
						progressPercent: (2934 / maxDistance * 100).toFixed(1)
					},
					{
						rank: 4,
						name: "StormChaser",
						distance: 2847,
						power: 267,
						timestamp: new Date(now - 2 * 60 * 60 * 1000), // 2 hours ago (today's record)
						floodSpeed: 0.8,
						maxDistance: maxDistance,
						progressPercent: (2847 / maxDistance * 100).toFixed(1)
					},
					{
						rank: 5,
						name: "DeepSeaExplorer",
						distance: 2756,
						power: 312,
						timestamp: new Date(now - 4 * 24 * 60 * 60 * 1000), // 4 days ago
						floodSpeed: 1.3,
						maxDistance: maxDistance,
						progressPercent: (2756 / maxDistance * 100).toFixed(1)
					},
					{
						rank: 6,
						name: "TidalMaster",
						distance: 2689,
						power: 234,
						timestamp: new Date(now - 5 * 24 * 60 * 60 * 1000), // 5 days ago
						floodSpeed: 0.7,
						maxDistance: maxDistance,
						progressPercent: (2689 / maxDistance * 100).toFixed(1)
					}
				];
			}

			// Initialize round timer
			let startTime = Date.now();
			function updateRoundTimer() {
				const elapsed = Math.floor((Date.now() - startTime) / 1000);
				const minutes = Math.floor(elapsed / 60);
				const seconds = elapsed % 60;
				$scope.roundTime = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
				
				if (!$scope.$$phase) {
					$scope.$apply();
				}
			}

			// Start the timer
			const timerInterval = setInterval(updateRoundTimer, 1000);

			// Initialize all test data
			initializeCurrentData();
			initializeDailyData();
			initializeWeeklyData();

			// Mouse and focus event handlers
			element.on('mouseenter', function() {
				$scope.setAppFocus(true);
			});

			element.on('mouseleave', function() {
				// Add a small delay before hiding to prevent flickering
				setTimeout(function() {
					if (!element.is(':focus-within')) {
						$scope.setAppFocus(false);
					}
				}, 100);
			});

			element.on('focusin', function() {
				$scope.setAppFocus(true);
			});

			element.on('focusout', function() {
				// Check if focus moved to a child element
				setTimeout(function() {
					if (!element.is(':focus-within')) {
						$scope.setAppFocus(false);
					}
				}, 100);
			});

			// Cleanup function
			$scope.$on('$destroy', function() {
				if (timerInterval) {
					clearInterval(timerInterval);
				}
				element.off('mouseenter mouseleave focusin focusout');
			});

			// TODO: Future implementation for receiving data from game
			/*
			$scope.$on('streamsUpdate', function (event, streams) {
				// Handle current round data updates here
			});

			function getLeaderboardData() {
				bngApi.engineLua(luaScript, (result) => {
					// Process current leaderboard data from game
				});
			}

			function getDailyRecords() {
				bngApi.engineLua(dailyRecordsScript, (result) => {
					// Process daily records from game
				});
			}

			function getWeeklyRecords() {
				bngApi.engineLua(weeklyRecordsScript, (result) => {
					// Process weekly records from game
				});
			}
			*/
		}
	}
}]);

