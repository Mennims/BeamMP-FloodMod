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
			$scope.roundStartTime = 0;

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

			// Handle leaderboard data from server
			function handleLeaderboardUpdate(data) {
				if (!data) return;
				
				try {
					const leaderboardData = JSON.parse(data);
					
					// Update current round data
					if (leaderboardData.currentRound) {
						$scope.leaderboardData = leaderboardData.currentRound.map((entry, index) => ({
							rank: entry.position,
							name: entry.name,
							vehicle: entry.vehicleName || "Unknown Vehicle",
							distance: Math.floor(entry.minDistance),
							power: entry.enginePower,
							currentDistance: Math.floor(entry.currentDistance),
							totalDistance: Math.floor(entry.maxDistance),
							progressPercent: entry.progressPercent,
							resetsUsed: entry.resetsUsed,
							isCurrentPlayer: false, // TODO: Determine current player
							isAlive: entry.isAlive
						}));
					}
					
					// Update daily records
					if (leaderboardData.dailyRecords) {
						$scope.dailyRecords = leaderboardData.dailyRecords.map((record, index) => ({
							rank: record.position,
							name: record.name,
							distance: Math.floor(record.finalDistance),
							power: record.enginePower,
							timestamp: new Date(record.timestamp * 1000), // Convert from Unix timestamp
							floodSpeed: record.floodSpeed,
							maxDistance: Math.floor(record.maxDistance),
							progressPercent: record.progressPercent,
							resetsUsed: record.resetsUsed
						}));
					}
					
					// Update weekly records
					if (leaderboardData.weeklyRecords) {
						$scope.weeklyRecords = leaderboardData.weeklyRecords.map((record, index) => ({
							rank: record.position,
							name: record.name,
							distance: Math.floor(record.finalDistance),
							power: record.enginePower,
							timestamp: new Date(record.timestamp * 1000), // Convert from Unix timestamp
							floodSpeed: record.floodSpeed,
							maxDistance: Math.floor(record.maxDistance),
							progressPercent: record.progressPercent,
							resetsUsed: record.resetsUsed
						}));
					}
					
					if (!$scope.$$phase) {
						$scope.$apply();
					}
				} catch (error) {
					console.error('Error parsing leaderboard data:', error);
				}
			}

			// Initialize empty data - will be populated by server updates
			function initializeEmptyData() {
				$scope.leaderboardData = [];
				$scope.dailyRecords = [];
				$scope.weeklyRecords = [];
			}

			// Initialize round timer
			function updateRoundTimer() {
				if ($scope.roundStartTime > 0) {
					const elapsed = Math.floor((Date.now() / 1000) - $scope.roundStartTime);
					const minutes = Math.floor(elapsed / 60);
					const seconds = elapsed % 60;
					$scope.roundTime = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
				} else {
					$scope.roundTime = "00:00";
				}
				
				if (!$scope.$$phase) {
					$scope.$apply();
				}
			}

			// Start the timer
			const timerInterval = setInterval(updateRoundTimer, 1000);

			// Initialize empty data - server will populate it
			initializeEmptyData();

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

			// Set up event handler for receiving leaderboard data from server
			$scope.handleLeaderboardUpdate = handleLeaderboardUpdate;
			
			// Listen for leaderboard updates from the game
			$scope.$on('LeaderboardUpdate', function(event, data) {
				handleLeaderboardUpdate(data);
			});
			
			// Listen for round start events
			$scope.$on('RoundStarted', function(event, startTime) {
				$scope.roundStartTime = startTime;
				if (!$scope.$$phase) {
					$scope.$apply();
				}
			});
		}
	}
}]);

