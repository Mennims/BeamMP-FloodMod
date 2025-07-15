'use strict'
angular.module("beamng.apps").directive("vehiclespectators", [function () {
	return {
		templateUrl: '/ui/modules/apps/vehiclespectators/app.html',
		replace: true,
		link: function ($scope, element, attrs) {
			// Cleanup tracking
			let isDestroyed = false;
			let updateInterval = null;

			// Initialize scope variables
			$scope.currentVehicle = {
				inVehicle: false,
				isDriving: false,
				isSpectating: false,
				serverVehicleID: null,
				gameVehicleID: null,
				vehicleOwner: null
			};
			$scope.spectators = [];
			$scope.maxVisibleSpectators = 7; // Show max 8 spectator names before showing "+X more"

			// Lua code to get current vehicle info and occupants
			const LuaGetCurrentVehicleInfo = `
				(function()
					if SpectatePro.getCurrentVehicleInfo then
						return SpectatePro.getCurrentVehicleInfo()
					end
					return {
						inVehicle = false,
						isDriving = false,
						isSpectating = false,
						serverVehicleID = nil,
						gameVehicleID = nil,
						vehicleOwner = nil
					}
				end)()`;

			const LuaGetCurrentVehicleOccupants = `
				(function()
					if SpectatePro.getCurrentVehicleOccupants then
						return SpectatePro.getCurrentVehicleOccupants()
					end
					return {}
				end)()`;

			// Dummy data for testing (comment out when using real data)
			const dummyVehicleInfo = {
				inVehicle: true,
				isDriving: false,
				isSpectating: true,
				serverVehicleID: 12345,
				gameVehicleID: 67890,
				vehicleOwner: "SpeedDemon"
			};

			const dummyOccupants = [
				{
					playerID: 1,
					name: "SpeedDemon",
					isOwner: true,
					isDriver: true,
					isLocal: false
				},
				{
					playerID: 2,
					name: "RacingFan",
					isOwner: false,
					isDriver: false,
					isLocal: true
				},
				{
					playerID: 3,
					name: "CarEnthusiast",
					isOwner: false,
					isDriver: false,
					isLocal: false
				},
				{
					playerID: 4,
					name: "DriftKing",
					isOwner: false,
					isDriver: false,
					isLocal: false
				},
				{
					playerID: 5,
					name: "TurboBoost",
					isOwner: false,
					isDriver: false,
					isLocal: false
				},
				{
					playerID: 6,
					name: "NitroRacer",
					isOwner: false,
					isDriver: false,
					isLocal: false
				},
				{
					playerID: 7,
					name: "SpeedFreak",
					isOwner: false,
					isDriver: false,
					isLocal: false
				},
				{
					playerID: 8,
					name: "RacingPro",
					isOwner: false,
					isDriver: false,
					isLocal: false
				},
				{
					playerID: 9,
					name: "CarMaster",
					isOwner: false,
					isDriver: false,
					isLocal: false
				},
				{
					playerID: 10,
					name: "DriftPro",
					isOwner: false,
					isDriver: false,
					isLocal: false
				},
				{
					playerID: 11,
					name: "TurboMaster",
					isOwner: false,
					isDriver: false,
					isLocal: false
				},
				{
					playerID: 12,
					name: "NitroKing",
					isOwner: false,
					isDriver: false,
					isLocal: false
				}
			];

			// Function to separate spectators from driver
			function separateSpectators(occupants) {
				const spectators = [];
				
				for (const occupant of occupants) {
					if (!occupant.isOwner) {
						spectators.push(occupant);
					}
				}
				
				return spectators;
			}

			// Function to update vehicle and occupant information
			function updateVehicleInfo() {
				if (isDestroyed) return;

				// Use dummy data for testing (comment out this section when using real data)
				
				// $scope.currentVehicle = dummyVehicleInfo;
				// $scope.spectators = separateSpectators(dummyOccupants);
				// $scope.$apply();
				

				// Get current vehicle info
				bngApi.engineLua(LuaGetCurrentVehicleInfo, (vehicleInfo) => {
					if (isDestroyed) return;
					
					if (vehicleInfo && typeof vehicleInfo === 'object') {
						$scope.currentVehicle = vehicleInfo;
						
						// Only get occupants if we're in a vehicle with a server ID
						if (vehicleInfo.inVehicle && vehicleInfo.serverVehicleID) {
							bngApi.engineLua(LuaGetCurrentVehicleOccupants, (occupants) => {
								if (isDestroyed) return;
								
								if (occupants && Array.isArray(occupants)) {
									$scope.spectators = separateSpectators(occupants);
								} else {
									$scope.spectators = [];
								}
								$scope.$apply();
							});
						} else {
							$scope.spectators = [];
						}
					}
					$scope.$apply();
				});
			}

			// Set up periodic updates
			function startUpdates() {
				if (isDestroyed) return;
				
				// Update immediately
				updateVehicleInfo();
				
				// Set up interval for updates (every 1 second)
				updateInterval = setInterval(() => {
					if (isDestroyed) return;
					updateVehicleInfo();
				}, 1000);
			}

			// Start the update cycle
			startUpdates();

			// Cleanup function
			function cleanup() {
				isDestroyed = true;

				// Clear update interval
				if (updateInterval) {
					clearInterval(updateInterval);
					updateInterval = null;
				}
			}

			// Register cleanup on scope destroy
			$scope.$on('$destroy', cleanup);
			
			// Also cleanup on element removal
			element.on('$destroy', cleanup);
		}
	}
}]); 