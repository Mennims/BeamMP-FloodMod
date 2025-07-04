'use strict'
angular.module("beamng.apps").directive("floodsealevel", [function () {
	return {
		templateUrl: '/ui/modules/apps/floodsealevel/app.html',
		replace: true,
		link: function ($scope, element, attrs) {
			function loadScript(url) {
				return new Promise((resolve, reject) => {
					const script = document.createElement('script');
					script.src = url;
					script.onload = resolve;
					script.onerror = reject;
					document.head.appendChild(script);
				});
			}

			async function loadAllScripts() {
				try {
					await loadScript('/ui/modules/apps/floodsealevel/wave/js/Wave.js');

					if (window.Wave) {
						setTimeout(() => {
							setTimeout(() => {
								Wave.init();
							}, 250);
						});
						
						
					}
				} catch (error) {}
			}

			if (window.Wave) {
				window.Wave = undefined;
				loadAllScripts();
			} else {
				loadAllScripts();
			}

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

			const appContainer = document.getElementById('app-container');
			const seaContainer = document.getElementById('sea-container');
			
			let playerVehicleZ = 0;
			let seaLevel = 0;

			$scope.seaPosition = 0;
			$scope.difference = 0;
			$scope.seaLevel = 0;

			seaContainer.hidden = true;

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
				socialsText.innerHTML = text;
				socialsText.style.opacity = '1';
				
				setTimeout(() => {
					socialsText.style.opacity = '0';
				}, 2000);
			}

			function pulseSocials() {
				const discordElement = document.querySelector('.wave-app .socials-container .discord-container');
				const patreonElement = document.querySelector('.wave-app .socials-container .patreon-container');
				if (discordElement && patreonElement) {
					patreonElement.classList.add('active');
					setTimeout(() => {
						patreonElement.classList.remove('active');
					}, 1700);
					
					setTimeout(() => {
						discordElement.classList.add('active');
						setTimeout(() => {
							discordElement.classList.remove('active');
						}, 1500);
					}, 300);	
				}
			}

			function schedulePulseSocials() {
				const minInterval = 120000;
				const maxInterval = 240000;
				const randomInterval = Math.floor(Math.random() * (maxInterval - minInterval + 1)) + minInterval;
				
				setTimeout(() => {
					pulseSocials();
					schedulePulseSocials();
				}, randomInterval);
			}

			let pulseScheduled = false;
			if (!pulseScheduled) {
				schedulePulseSocials();
				pulseScheduled = true;
			}

			$scope.$$listeners.streamsUpdate = [];

			$scope.$on('streamsUpdate', function (event, streams) {
				playerVehicleZ = streams.sensors.position.z;
				bngApi.engineLua(LuaSeaLevel, (seaLevelResult) => {
					seaLevel = seaLevelResult;
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

					const multiplier = Math.pow(10, 1);
					$scope.difference = Math.round((playerVehicleZ - seaLevel) * multiplier) / multiplier;

					$scope.difference = $scope.difference.toFixed(1)

					if (seaContainer.hidden) {
						seaContainer.hidden = false;
					}
				}
			});
		}
	}
}]);

