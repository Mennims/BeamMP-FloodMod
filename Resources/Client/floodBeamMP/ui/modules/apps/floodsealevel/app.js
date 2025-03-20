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
						Wave.init();
					}
				} catch (error) {
				}
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

			const appContainer = document.getElementById('app-container');
			const seaContainer = document.getElementById('sea-container');
			
			let playerVehicleZ = null;
			let seaLevel = null;

			$scope.seaPosition = 0;
			$scope.difference = 0;
			$scope.seaLevel = null;

			seaContainer.hidden = true;

			$scope.$on('streamsUpdate', function (event, streams) {
				playerVehicleZ = streams.sensors.position.z;
				bngApi.engineLua(LuaSeaLevel, (seaLevelResult) => {
					seaLevel = seaLevelResult;
				});

				if (playerVehicleZ && seaLevel && seaContainer) {
					const maxMovement = appContainer.offsetHeight;
					const gain = 0.23;
					const minDistance = 0.01;

					const distance = Math.max($scope.difference, minDistance);
					const scaledMovement = maxMovement * Math.log10(distance) * gain;

					$scope.seaPosition =(scaledMovement + (appContainer.offsetHeight * 0.3));
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

