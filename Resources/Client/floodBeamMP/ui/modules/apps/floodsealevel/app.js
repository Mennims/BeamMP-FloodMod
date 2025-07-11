'use strict'
angular.module("beamng.apps").directive("floodsealevel", [function () {
	return {
		templateUrl: '/ui/modules/apps/floodsealevel/app.html',
		replace: true,
		link: function ($scope, element, attrs) {
			// Cleanup tracking
			let timeoutIds = [];
			let isDestroyed = false;
			
			function loadScript(url) {
				return new Promise((resolve, reject) => {
					// Check if script already exists
					const existingScript = document.querySelector(`script[src="${url}"]`);
					if (existingScript) {
						resolve();
						return;
					}
					
					const script = document.createElement('script');
					script.src = url;
					script.onload = resolve;
					script.onerror = reject;
					document.head.appendChild(script);
					
					// Track script for cleanup
					script.setAttribute('data-flood-app', 'true');
				});
			}

			async function loadAllScripts() {
				if (isDestroyed) return;
				
				try {
					await loadScript('/ui/modules/apps/floodsealevel/wave/js/Wave.js');

					if (window.Wave && !isDestroyed) {
						const timeoutId = setTimeout(() => {
							if (isDestroyed) return;
							const innerTimeoutId = setTimeout(() => {
								if (isDestroyed) return;
								if (window.Wave && typeof window.Wave.init === 'function') {
									Wave.init();
								}
							}, 250);
							timeoutIds.push(innerTimeoutId);
						});
						timeoutIds.push(timeoutId);
					}
				} catch (error) {
					console.warn('Failed to load Wave.js:', error);
				}
			}

			// Clean up existing Wave instance if it exists
			if (window.Wave && typeof window.Wave.destroy === 'function') {
				window.Wave.destroy();
			}
			
			loadAllScripts();

			const LuaSeaLevel = `
				(function()
					local function findObject(objectName, className)
						local obj = scenetree.findObject(objectName)
						if obj then return obj end
						if not className then return nil end

						local objects = scenetree.findClassObjects(className)
						for _, name in pairs(objects) do
							local object = scenetree.findObject(name)
							if string.find(name, objectName) then return object end
						end

						return
					end

					local function getWaterLevel(ocean)
						if not ocean then return nil end
						return ocean.position:getColumn(3).z
					end

					return getWaterLevel(findObject("Ocean", "WaterPlane"))
				end)()`;

			const LuaFloodSpeed = `
				(function()
					if floodBeamMP and floodBeamMP.state and type(floodBeamMP.state.floodSpeed) == 'number' then
						return floodBeamMP.state.floodSpeed
					end
					return 0
				end)()`;

			const LuaFloodState = `
				(function()
					if floodBeamMP and floodBeamMP.state and floodBeamMP.state.floodState then
						return floodBeamMP.state.floodState
					end
					return {status = "stopped", speed = 0, level = 0, lastUpdate = 0}
				end)()`;

			const appContainer = document.getElementById('app-container');
			const seaContainer = document.getElementById('sea-container');
			
			let playerVehicleZ = 0;
			let seaLevel = 0;
			let floodSpeed = 0;

			$scope.seaPosition = 0;
			$scope.difference = 0;
			$scope.seaLevel = 0;
			$scope.floodSpeed = 0;
			$scope.floodState = {
				status: "stopped",
				speed: 0,
				level: 0,
				lastUpdate: 0
			};

			if (seaContainer) {
				seaContainer.hidden = true;
			}

			function copyToClipboard(text) {
				let textarea = document.createElement("textarea");
				textarea.value = text;
				document.body.appendChild(textarea);
				textarea.select();
				document.execCommand("copy");
				document.body.removeChild(textarea);
			}

			$scope.discord = () => {
				copyToClipboard('https://discord.gg/p6GTUMbEm8');
				$scope.showSocialsText('Link Copied');
			}

			$scope.patreon = () => {
				copyToClipboard('https://patreon.com/KeenanSmith');
				$scope.showSocialsText('Link Copied');
			}

			$scope.showSocialsText = (text) => {
				const socialsText = document.querySelector('.wave-app .socials-text');
				if (socialsText) {
					socialsText.innerHTML = text;
					socialsText.style.opacity = '1';
					
					const timeoutId = setTimeout(() => {
						if (isDestroyed || !socialsText) return;
						socialsText.style.opacity = '0';
					}, 2000);
					timeoutIds.push(timeoutId);
				}
			}

			function pulseSocials() {
				if (isDestroyed) return;
				
				const discordElement = document.querySelector('.wave-app .socials-container .discord-container');
				const patreonElement = document.querySelector('.wave-app .socials-container .patreon-container');
				if (discordElement && patreonElement) {
					patreonElement.classList.add('active');
					const timeoutId1 = setTimeout(() => {
						if (isDestroyed || !patreonElement) return;
						patreonElement.classList.remove('active');
					}, 1700);
					timeoutIds.push(timeoutId1);
					
					const timeoutId2 = setTimeout(() => {
						if (isDestroyed || !discordElement) return;
						discordElement.classList.add('active');
						const timeoutId3 = setTimeout(() => {
							if (isDestroyed || !discordElement) return;
							discordElement.classList.remove('active');
						}, 1500);
						timeoutIds.push(timeoutId3);
					}, 300);
					timeoutIds.push(timeoutId2);
				}
			}

			function schedulePulseSocials() {
				if (isDestroyed) return;
				
				const minInterval = 120000; // 2 minutes
				const maxInterval = 240000; // 4 minutes
				const randomInterval = Math.floor(Math.random() * (maxInterval - minInterval + 1)) + minInterval;
				
				const timeoutId = setTimeout(() => {
					if (isDestroyed) return;
					pulseSocials();
					schedulePulseSocials(); // Recursive call
				}, randomInterval);
				timeoutIds.push(timeoutId);
			}

			// Start the pulse scheduling
			schedulePulseSocials();

			// Flood status handling functions
			$scope.getFloodStatusText = function() {
				if (!$scope.floodState) return 'FLOOD STOPPED';
				
				switch($scope.floodState.status) {
					case 'stopped':
						return 'FLOOD STOPPED';
					case 'auto_countdown':
						return 'AUTO STARTING...';
					case 'countdown':
						return 'STARTING...';
					case 'active':
						return 'FLOOD ACTIVE';
					default:
						return 'FLOOD STOPPED';
				}
			};

			$scope.getFloodStatusClass = function() {
				if (!$scope.floodState || !$scope.floodState.status) return 'flood-status-stopped';
				return 'flood-status-' + $scope.floodState.status;
			};

			$scope.getCarIconClass = function() {
				const distance = parseFloat($scope.difference) || 0;
				
				if (distance <= 10) {
					return 'car-danger'; // Red pulse
				} else if (distance <= 20) {
					return 'car-warning'; // Yellow pulse
				} else {
					return 'car-safe'; // Green pulse
				}
			};

			// Difficulty indicator based on flood speed
			$scope.getDifficultyText = function() {
				const speed = parseFloat($scope.floodSpeed) || 0;
				
				if (speed < 1.25) {
					return 'Very Easy';
				} else if (speed < 1.75) {
					return 'Easy';
				} else if (speed < 2.00) {
					return 'Normal';
				} else if (speed < 2.25) {
					return 'Intermediate';
				} else if (speed < 2.50) {
					return 'Hard';
				} else if (speed < 2.75) {
					return 'Very Hard';
				} else if (speed < 3.00) {
					return 'Extreme';
				} else {
					return 'Impossible';
				}
			};

			$scope.getDifficultyClass = function() {
				const speed = parseFloat($scope.floodSpeed) || 0;
				
				if (speed < 1.25) {
					return 'difficulty-very-easy';
				} else if (speed < 1.75) {
					return 'difficulty-easy';
				} else if (speed < 2.00) {
					return 'difficulty-normal';
				} else if (speed < 2.25) {
					return 'difficulty-intermediate';
				} else if (speed < 2.50) {
					return 'difficulty-hard';
				} else if (speed < 2.75) {
					return 'difficulty-very-hard';
				} else if (speed < 3.00) {
					return 'difficulty-extreme';
				} else {
					return 'difficulty-impossible';
				}
			};

			// Listen for flood state updates
			$scope.$on('FloodStateUpdate', function(event, floodState) {
				if (isDestroyed) return;
				if (floodState && typeof floodState === 'object') {
					$scope.floodState = floodState;
					$scope.floodSpeed = floodState.speed || 0; // Update flood speed
				}
				$scope.$apply();
			});

			// Clean up existing listeners to prevent duplicates
			$scope.$$listeners.streamsUpdate = [];

			$scope.$on('streamsUpdate', function (event, streams) {
				if (isDestroyed) return;
				
				playerVehicleZ = streams.sensors.position.z;
				bngApi.engineLua(LuaSeaLevel, (seaLevelResult) => {
					if (isDestroyed) return;
					seaLevel = seaLevelResult;
				});
				
				bngApi.engineLua(LuaFloodSpeed, (floodSpeedResult) => {
					if (isDestroyed) return;
					floodSpeed = floodSpeedResult;
				});
				
				bngApi.engineLua(LuaFloodState, (floodStateResult) => {
					if (isDestroyed) return;
					if (floodStateResult && typeof floodStateResult === 'object') {
						$scope.floodState = floodStateResult;
					}
				});

				if (playerVehicleZ && seaLevel && seaContainer && appContainer) {
					const maxMovement = appContainer.offsetHeight;
					const gain = 0.7;
					const minDistance = 0.01;

					const distance = Math.max($scope.difference, minDistance);
					const scaledMovement = maxMovement * Math.log10(distance) * gain;

					let newSeaPosition = (scaledMovement + (appContainer.offsetHeight - (appContainer.offsetHeight * 1.4)));

					const minSeaPosition = maxMovement * 0.97;

					if (newSeaPosition > minSeaPosition) {
						$scope.seaPosition = minSeaPosition;
					} else if (newSeaPosition < 0) {
						$scope.seaPosition = 0;
					} else {
						$scope.seaPosition = newSeaPosition;
					}

					$scope.seaLevel = seaLevel;
					$scope.floodSpeed = floodSpeed;

					const multiplier = Math.pow(10, 1);
					$scope.difference = Math.round((playerVehicleZ - seaLevel) * multiplier) / multiplier;

					$scope.difference = $scope.difference.toFixed(1)

					if (seaContainer && seaContainer.hidden) {
						seaContainer.hidden = false;
					}
				}
			});

			// Cleanup function
			function cleanup() {
				isDestroyed = true;
				
				// Clear all timeouts
				timeoutIds.forEach(id => clearTimeout(id));
				timeoutIds = [];
				
				// Clean up Wave instance
				if (window.Wave && typeof window.Wave.destroy === 'function') {
					window.Wave.destroy();
				}
				
				// Remove any scripts added by this instance
				const scripts = document.querySelectorAll('script[data-flood-app="true"]');
				scripts.forEach(script => {
					if (script.parentNode) {
						script.parentNode.removeChild(script);
					}
				});
			}

			// Register cleanup on scope destroy
			$scope.$on('$destroy', cleanup);
			
			// Also cleanup on element removal
			element.on('$destroy', cleanup);
		}
	}
}]);

