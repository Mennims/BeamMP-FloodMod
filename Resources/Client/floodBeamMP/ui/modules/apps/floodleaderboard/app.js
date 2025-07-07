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
			$scope.roundStartTime = 0;
			$scope.isRoundActive = false;
			$scope.showTabsTemporarily = false;
			$scope.playerFinishTimes = {}; // Track finish times for each player
			$scope.hasWinner = false; // Track if someone has won
			$scope.winnerName = ""; // Track winner name

			// Memory leak prevention and performance optimization
			let timerInterval = null;
			let focusTimeout = null;
			let tabShowTimeout = null;
			let isAppSuspended = false;
			let isDestroyed = false;
			let lastUpdateTime = 0;
			const UPDATE_THROTTLE_MS = 100; // Throttle rapid updates
			
			// Event listener deregistration functions
			let eventDeregistrationFunctions = [];
			
			// Safe timeout/interval management
			function safeSetTimeout(callback, delay) {
				if (isDestroyed) return null;
				return setTimeout(function() {
					if (!isDestroyed) callback();
				}, delay);
			}
			
			function safeSetInterval(callback, delay) {
				if (isDestroyed) return null;
				return setInterval(function() {
					if (!isDestroyed && !isAppSuspended) callback();
				}, delay);
			}
			
			function safeClearTimeout(timeoutId) {
				if (timeoutId) {
					clearTimeout(timeoutId);
					return null;
				}
			}
			
			function safeClearInterval(intervalId) {
				if (intervalId) {
					clearInterval(intervalId);
					return null;
				}
			}

			// Suspension handling for BeamMP pause menu
			function handleAppSuspension(suspended) {
				isAppSuspended = suspended;
				if (suspended) {
					// App is suspended (pause menu shown), stop all timers to prevent memory leaks
					console.log('[FloodLeaderboard] App suspended - pausing timers');
				} else {
					// App resumed, restart timers if needed
					console.log('[FloodLeaderboard] App resumed - restarting timers');
				}
			}

			// Focus management with debouncing to prevent flickering
			$scope.setAppFocus = function(focused) {
				if (isDestroyed) return;
				
				// Clear any pending focus changes
				focusTimeout = safeClearTimeout(focusTimeout);
				
				if (focused) {
					// Immediately focus when entering
					$scope.isAppFocused = true;
				} else {
					// Delay unfocus to prevent flickering when clicking tabs
					focusTimeout = safeSetTimeout(function() {
						if (!isDestroyed) {
							$scope.isAppFocused = false;
							// Reset to current race tab when losing focus
							$scope.activeTab = 'current';
							$scope.$apply();
						}
					}, 100); // 100ms delay
				}
			};

			// Tab management
			$scope.setActiveTab = function(tab) {
				if (isDestroyed) return;
				
				$scope.activeTab = tab;
				// Ensure we stay focused when switching tabs
				$scope.setAppFocus(true);
				
				// If user clicks a tab during temporary display, cancel the auto-hide
				if ($scope.showTabsTemporarily && tabShowTimeout) {
					tabShowTimeout = safeClearTimeout(tabShowTimeout);
					$scope.showTabsTemporarily = false; // Let normal focus take over
				}
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

			$scope.getPlayerCount = function() {
				switch($scope.activeTab) {
					case 'current': return $scope.leaderboardData.length;
					case 'daily': return $scope.dailyRecords.length;
					case 'weekly': return $scope.weeklyRecords.length;
					default: return 0;
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

			$scope.formatTime = function(seconds) {
				if (!seconds || seconds <= 0) return "0:00";
				
				const totalSeconds = Math.floor(seconds);
				const minutes = Math.floor(totalSeconds / 60);
				const remainingSeconds = totalSeconds % 60;
				
				if (minutes >= 60) {
					const hours = Math.floor(minutes / 60);
					const remainingMinutes = minutes % 60;
					return `${hours}:${remainingMinutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
				} else {
					return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
				}
			};

			// Get the appropriate time for display (finish time if finished, otherwise time alive)
			$scope.getDisplayTime = function(player) {
				if (player.hasFinished && player.finishTime > 0) {
					// Finish time is already a duration (calculated server-side)
					return $scope.formatTime(player.finishTime);
				} else {
					// Use time alive for ongoing or dead players
					return $scope.formatTime(player.timeAlive);
				}
			};

			// Get the appropriate time for historical records
			$scope.getHistoricalTime = function(record) {
				// For historical records, prioritize finish time if it exists and is greater than 0
				// Otherwise fall back to time alive
				if (record.finishTime && record.finishTime > 0) {
					// For finished players, the finishTime from server is already the duration
					// (calculated as finishTime - roundStartTime on the server)
					return $scope.formatTime(record.finishTime);
				} else {
					// For non-finishers or when finish time is not available, show time alive
					return $scope.formatTime(record.timeAlive || 0);
				}
			};

			// Throttled update function to prevent excessive DOM updates
			function throttledApply() {
				const now = Date.now();
				if (now - lastUpdateTime >= UPDATE_THROTTLE_MS && !isDestroyed && !isAppSuspended) {
					lastUpdateTime = now;
					$scope.$apply();
				}
			}

			// Handle fast current round updates (during race)
			function handleCurrentRoundUpdate(data) {
				if (!data || isDestroyed || isAppSuspended) return;
				
				try {
					const leaderboardData = JSON.parse(data);
					
					// Update only current round data (fast updates during race)
					if (leaderboardData.currentRound && Array.isArray(leaderboardData.currentRound)) {
						$scope.leaderboardData = leaderboardData.currentRound.map((entry, index) => ({
							rank: entry.position,
							name: entry.name,
							vehicle: entry.vehicleName || "Unknown Vehicle",
							distance: Math.floor(entry.bestDistanceTraveled || 0), // Best distance traveled
							power: entry.enginePower,
							currentDistance: Math.floor(entry.bestDistanceTraveled || 0), // Best distance traveled
							totalDistance: Math.floor(entry.trackLength),
							progressPercent: entry.progressPercent,
							resetsUsed: entry.resetsUsed,
							timeAlive: entry.timeAlive || 0,
							isCurrentPlayer: false, // TODO: Determine current player
							isAlive: entry.isAlive,
							hasWon: entry.hasWon || false,
							hasFinished: entry.hasFinished || false,
							finishTime: entry.finishTime || 0
						}));
						throttledApply(); // Use throttled apply for performance
					}
				} catch (error) {
					console.error('Error parsing current round leaderboard data:', error);
				}
			}

			// Handle leaderboard data from server
			function handleLeaderboardUpdate(data) {
				if (!data || isDestroyed || isAppSuspended) return;
				
				try {
					const leaderboardData = JSON.parse(data);
					
					// Update current round data
				if (leaderboardData.currentRound && Array.isArray(leaderboardData.currentRound)) {
					$scope.leaderboardData = leaderboardData.currentRound.map((entry, index) => ({
						rank: entry.position,
						name: entry.name,
						vehicle: entry.vehicleName || "Unknown Vehicle",
						distance: Math.floor(entry.bestDistanceTraveled || 0), // Best distance traveled
						power: entry.enginePower,
						currentDistance: Math.floor(entry.bestDistanceTraveled || 0), // Best distance traveled
						totalDistance: Math.floor(entry.trackLength),
						progressPercent: entry.progressPercent,
						resetsUsed: entry.resetsUsed,
						timeAlive: entry.timeAlive || 0,
						isCurrentPlayer: false, // TODO: Determine current player
						isAlive: entry.isAlive,
						hasWon: entry.hasWon || false,
						hasFinished: entry.hasFinished || false,
						finishTime: entry.finishTime || 0
					}));
				} else {
					// No current round data, initialize empty array
					$scope.leaderboardData = [];
				}
					
				// Update daily records
				if (leaderboardData.dailyRecords && Array.isArray(leaderboardData.dailyRecords)) {
					$scope.dailyRecords = leaderboardData.dailyRecords.map((record, index) => ({
						rank: record.position,
						name: record.name,
						distance: Math.floor(record.finalDistanceTraveled || 0), // Distance traveled
						power: record.enginePower,
						timeAlive: record.timeAlive || 0,
						finishTime: record.finishTime || 0,
						timestamp: new Date(record.timestamp * 1000), // Convert from Unix timestamp
						floodSpeed: Math.round(record.floodSpeed * 100) / 100, // Round to 2 decimal places
						maxDistance: Math.floor(record.trackLength),
						progressPercent: record.progressPercent,
						resetsUsed: record.resetsUsed,
						vehicle: record.vehicleName || "Unknown Vehicle"
					}));
				} else {
					// No daily records, keep existing or initialize empty
					$scope.dailyRecords = $scope.dailyRecords || [];
				}
				
				// Update weekly records
				if (leaderboardData.weeklyRecords && Array.isArray(leaderboardData.weeklyRecords)) {
					$scope.weeklyRecords = leaderboardData.weeklyRecords.map((record, index) => ({
						rank: record.position,
						name: record.name,
						distance: Math.floor(record.finalDistanceTraveled || 0), // Distance traveled
						power: record.enginePower,
						timeAlive: record.timeAlive || 0,
						finishTime: record.finishTime || 0,
						timestamp: new Date(record.timestamp * 1000), // Convert from Unix timestamp
						floodSpeed: Math.round(record.floodSpeed * 100) / 100, // Round to 2 decimal places
						maxDistance: Math.floor(record.trackLength),
						progressPercent: record.progressPercent,
						resetsUsed: record.resetsUsed,
						vehicle: record.vehicleName || "Unknown Vehicle"
					}));
				} else {
					// No weekly records, keep existing or initialize empty
					$scope.weeklyRecords = $scope.weeklyRecords || [];
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
				
				// ========================================
				// DUMMY DATA FOR TESTING - REMOVE LATER
				// ========================================
				// loadDummyData();
			}
			
			// DUMMY DATA FUNCTION - COMMENT OUT OR REMOVE WHEN DONE TESTING
			function loadDummyData() {
				// Current round dummy data
				$scope.leaderboardData = [
					{
						rank: 1,
						name: "SpeedRacer",
						vehicle: "ETK K-Series",
						power: 250,
						progressPercent: 85.2,
						resetsUsed: 0,
						timeAlive: 143,
						currentDistance: 11163,
						totalDistance: 13098,
						isCurrentPlayer: false,
						isAlive: true
					},
					{
						rank: 2,
						name: "FloodSurvivor",
						vehicle: "Gavril Grand Marshal",
						power: 180,
						progressPercent: 78.9,
						resetsUsed: 1,
						timeAlive: 156,
						currentDistance: 10334,
						totalDistance: 13098,
						isCurrentPlayer: true,
						isAlive: true
					},
					{
						rank: 3,
						name: "WaterRunner",
						vehicle: "Hirochi Sunburst",
						power: 145,
						progressPercent: 71.3,
						resetsUsed: 0,
						timeAlive: 134,
						currentDistance: 9341,
						totalDistance: 13098,
						isCurrentPlayer: false,
						isAlive: true
					},
					{
						rank: 4,
						name: "DeepDriver",
						vehicle: "Ibishu Covet",
						power: 95,
						progressPercent: 64.7,
						resetsUsed: 2,
						timeAlive: 89,
						currentDistance: 8475,
						totalDistance: 13098,
						isCurrentPlayer: false,
						isAlive: false
					},
					{
						rank: 5,
						name: "AquaVelocity",
						vehicle: "Bruckell Moonhawk",
						power: 210,
						progressPercent: 58.1,
						resetsUsed: 3,
						timeAlive: 67,
						currentDistance: 7609,
						totalDistance: 13098,
						isCurrentPlayer: false,
						isAlive: false
					},
					{
						rank: 6,
						name: "TidalWave",
						vehicle: "Soliad Wendover",
						power: 165,
						progressPercent: 45.3,
						resetsUsed: 1,
						timeAlive: 45,
						currentDistance: 5935,
						totalDistance: 13098,
						isCurrentPlayer: false,
						isAlive: false
					}
				];

				// Daily records dummy data
				$scope.dailyRecords = [
					{
						rank: 1,
						name: "ChampionDriverLongName",
						distance: 12456,
						power: 280,
						timeAlive: 289,
						timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000), // 2 hours ago
						floodSpeed: 0.05,
						maxDistance: 13098,
						progressPercent: 95.1,
						resetsUsed: 0,
						vehicle: "ETK K-Series"
					},
					{
						rank: 2,
						name: "ProRacer",
						distance: 11234,
						power: 245,
						timeAlive: 234,
						timestamp: new Date(Date.now() - 4 * 60 * 60 * 1000), // 4 hours ago
						floodSpeed: 0.06,
						maxDistance: 13098,
						progressPercent: 85.8,
						resetsUsed: 1,
						vehicle: "Gavril Grand Marshal"
					},
					{
						rank: 3,
						name: "FloodMaster",
						distance: 10987,
						power: 190,
						timeAlive: 198,
						timestamp: new Date(Date.now() - 6 * 60 * 60 * 1000), // 6 hours ago
						floodSpeed: 0.055,
						maxDistance: 13098,
						progressPercent: 83.9,
						resetsUsed: 0,
						vehicle: "Hirochi Sunburst"
					},
					{
						rank: 4,
						name: "WaveRider",
						distance: 9876,
						power: 165,
						timeAlive: 167,
						timestamp: new Date(Date.now() - 8 * 60 * 60 * 1000), // 8 hours ago
						floodSpeed: 0.07,
						maxDistance: 13098,
						progressPercent: 75.4,
						resetsUsed: 2,
						vehicle: "Ibishu Covet"
					}
				];

				// Weekly records dummy data
				$scope.weeklyRecords = [
					{
						rank: 1,
						name: "WeeklyKing",
						distance: 12891,
						power: 320,
						timeAlive: 345,
						timestamp: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000), // 2 days ago
						floodSpeed: 0.045,
						maxDistance: 13098,
						progressPercent: 98.4,
						resetsUsed: 0,
						vehicle: "Gavril Barstow"
					},
					{
						rank: 2,
						name: "LegendaryDriver",
						distance: 12567,
						power: 290,
						timeAlive: 312,
						timestamp: new Date(Date.now() - 3 * 24 * 60 * 60 * 1000), // 3 days ago
						floodSpeed: 0.05,
						maxDistance: 13098,
						progressPercent: 95.9,
						resetsUsed: 1,
						vehicle: "ETK K-Series"
					},
					{
						rank: 3,
						name: "FloodChampion",
						distance: 12123,
						power: 255,
						timeAlive: 287,
						timestamp: new Date(Date.now() - 5 * 24 * 60 * 60 * 1000), // 5 days ago
						floodSpeed: 0.055,
						maxDistance: 13098,
						progressPercent: 92.6,
						resetsUsed: 0,
						vehicle: "Bruckell Moonhawk"
					},
					{
						rank: 4,
						name: "AquaHero",
						distance: 11678,
						power: 220,
						timeAlive: 245,
						timestamp: new Date(Date.now() - 6 * 24 * 60 * 60 * 1000), // 6 days ago
						floodSpeed: 0.06,
						maxDistance: 13098,
						progressPercent: 89.2,
						resetsUsed: 1,
						vehicle: "Soliad Wendover"
					},
					{
						rank: 5,
						name: "DepthExplorer",
						distance: 11234,
						power: 185,
						timeAlive: 198,
						timestamp: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000), // 1 week ago
						floodSpeed: 0.065,
						maxDistance: 13098,
						progressPercent: 85.8,
						resetsUsed: 2,
						vehicle: "Hirochi SBR4"
					}
				];
				
				// Set round start time for testing
				$scope.roundStartTime = Math.floor(Date.now() / 1000) - 180; // Started 3 minutes ago
			}
			// ======================================== 
			// END DUMMY DATA - REMOVE ABOVE WHEN DONE
			// ========================================

			// Initialize round timer with suspension awareness
			function updateRoundTimer() {
				if (isDestroyed || isAppSuspended) return; // Don't update when suspended
				
				if ($scope.roundStartTime > 0 && $scope.isRoundActive) {
					const elapsed = Math.floor((Date.now() / 1000) - $scope.roundStartTime);
				const minutes = Math.floor(elapsed / 60);
				const seconds = elapsed % 60;
				$scope.roundTime = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
				} else if (!$scope.isRoundActive && $scope.roundStartTime > 0) {
					// Round has ended, keep the final time
					// Timer stops updating but shows final time
				} else {
					$scope.roundTime = "00:00";
				}
			}

			// Start the timer with safe interval management
			timerInterval = safeSetInterval(updateRoundTimer, 1000);

			// Initialize empty data - server will populate it
			initializeEmptyData();

			// Event listener registration with cleanup tracking
			function registerEventListener(eventName, handler) {
				const deregister = $scope.$on(eventName, handler);
				eventDeregistrationFunctions.push(deregister);
				return deregister;
			}

			// CRITICAL: Comprehensive cleanup function to prevent memory leaks
			$scope.$on('$destroy', function() {
				console.log('[FloodLeaderboard] Cleaning up resources...');
				isDestroyed = true;
				
				// Clear all timers and timeouts
				timerInterval = safeClearInterval(timerInterval);
				focusTimeout = safeClearTimeout(focusTimeout);
				tabShowTimeout = safeClearTimeout(tabShowTimeout);
				
				// Deregister all event listeners
				eventDeregistrationFunctions.forEach(function(deregister) {
					if (typeof deregister === 'function') {
						deregister();
					}
				});
				eventDeregistrationFunctions = [];
				
				// Clear scope data to prevent memory retention
				$scope.leaderboardData = null;
				$scope.dailyRecords = null;
				$scope.weeklyRecords = null;
				
				console.log('[FloodLeaderboard] Cleanup complete');
			});

			// Set up event handlers with proper cleanup tracking
			$scope.handleLeaderboardUpdate = handleLeaderboardUpdate;
			
			// Listen for leaderboard updates from the game
			registerEventListener('LeaderboardUpdate', function(event, data) {
				handleLeaderboardUpdate(data);
			});
			
			// Listen for fast current round updates during race
			registerEventListener('LeaderboardCurrentRoundUpdate', function(event, data) {
				handleCurrentRoundUpdate(data);
			});
			
			// Listen for round start events
			registerEventListener('RoundStarted', function(event, startTime) {
				if (!isDestroyed) {
					$scope.roundStartTime = startTime;
					$scope.isRoundActive = true;
					// Reset winner state for new round
					$scope.hasWinner = false;
					$scope.winnerName = "";
					$scope.playerFinishTimes = {};
				}
			});
			
			// Listen for round end events
			registerEventListener('RoundEnded', function(event, endData) {
				if (isDestroyed) return;
				
				$scope.isRoundActive = false;
				// Timer will stop updating but keep showing final time
				
				// Reset winner state for next round
				$scope.hasWinner = false;
				$scope.winnerName = "";
				$scope.playerFinishTimes = {};
				
				// Show tabs temporarily for 5 seconds when round ends
				$scope.showTabsTemporarily = true;
				$scope.isAppFocused = true; // Force focus to show tabs
				
				// Clear any existing timeout
				tabShowTimeout = safeClearTimeout(tabShowTimeout);
				
				// Hide tabs after 5 seconds and reset to current tab
				tabShowTimeout = safeSetTimeout(function() {
					if (!isDestroyed) {
						$scope.showTabsTemporarily = false;
						$scope.activeTab = 'current';
						$scope.isAppFocused = false; // Return to unfocused state
						$scope.$apply();
					}
				}, 5000); // 5 seconds
			});

			// Listen for player won events
			registerEventListener('PlayerWon', function(event, finishTime) {
				if (isDestroyed) return;
				
				// Stop the timer for the winning player (current player)
				console.log('[FloodLeaderboard] Player won at:', finishTime);
				// The timer will be handled by the finish time in the leaderboard data
			});

			// Listen for player finished events
			registerEventListener('PlayerFinished', function(event, finishData) {
				if (isDestroyed) return;
				
				try {
					const data = typeof finishData === 'string' ? JSON.parse(finishData) : finishData;
					
					if (data && data.playerId && data.finishTime) {
						// Store finish time for this player
						$scope.playerFinishTimes[data.playerId] = data.finishTime;
						
						if (data.isWinner) {
							$scope.hasWinner = true;
							$scope.winnerName = data.name;
							console.log('[FloodLeaderboard] Winner:', data.name);
						} else {
							console.log('[FloodLeaderboard] Player finished:', data.name);
						}
						
						$scope.$apply();
					}
				} catch (error) {
					console.error('Error parsing player finish data:', error);
				}
			});
			
			// Listen for app suspension events (BeamMP pause menu)
			registerEventListener('AppSuspended', function(event, suspended) {
				handleAppSuspension(suspended);
			});
			
			// Listen for visibility change events (alternative suspension detection)
			function handleVisibilityChange() {
				if (!isDestroyed) {
					handleAppSuspension(document.hidden || document.visibilityState === 'hidden');
				}
			}
			
			// Add visibility change listener if available
			if (typeof document !== 'undefined' && document.addEventListener) {
				document.addEventListener('visibilitychange', handleVisibilityChange);
				
				// Ensure this listener is also cleaned up
				eventDeregistrationFunctions.push(function() {
					if (typeof document !== 'undefined' && document.removeEventListener) {
						document.removeEventListener('visibilitychange', handleVisibilityChange);
					}
				});
			}
		}
	}
}]);

