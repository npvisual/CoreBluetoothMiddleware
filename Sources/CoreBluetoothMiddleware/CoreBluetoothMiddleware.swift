import CoreLocation
import CoreBluetooth
import SwiftRex

// MARK: - ACTION
public enum BluetoothAction {
    // Input
    case request(RequestAction)
    // Output
    case status(StatusAction)
}

public enum RequestAction {
    case requestManagerState(BTManagerType)
    case startAdvertising([String: Any])
    case stopAdvertising
}

public enum StatusAction {
    case gotManagerState(BTManagerType, CBManagerState)
    case gotStateRestoration(BTManagerType, [String: Any])
    case gotServiceAdditionAck(CBService)
    case gotSubscribedAck(CBCentral, CBCharacteristic)
    case gotUnsubscribed(CBCentral, CBCharacteristic)
    case gotAdvertisingAck
    case receivedError(Error)
}

public enum BTManagerType {
    case peripheral
    case central
}

// MARK: - STATE
public struct BluetoothState: Equatable {
    
    // Note : question is whether the state for those managers is
    // the same or not (i.e. could make that just one state ?)
    var statePeripheralManager: CBManagerState
    var stateCentralManager: CBManagerState
    
    public init(
        statePeripheralManager: CBManagerState = .unknown,
        stateCentralManager: CBManagerState = .unknown
    ) {
        self.statePeripheralManager = statePeripheralManager
        self.stateCentralManager = stateCentralManager
    }
}


// MARK: - REDUCERS

extension Reducer where ActionType == BluetoothAction, StateType == BluetoothState {
    static let location = Reducer<StatusAction, BluetoothState>.status.lift(action: \BluetoothAction.status)
}

extension Reducer where ActionType == StatusAction, StateType == BluetoothState {
    static let status = Reducer { action, state in
        var state = state
        switch action {
        case let .gotManagerState(type, status):
            switch type {
            case .peripheral: state.statePeripheralManager = status
            case .central: state.stateCentralManager = status
            }
        case .gotAdvertisingAck,
             .gotStateRestoration,
             .gotServiceAdditionAck,
             .gotSubscribedAck,
             .gotUnsubscribed,
             .receivedError:
            break
        }
        return state
    }
}


// MARK: - MIDDLEWARE
public final class CoreBluetoothMiddleware: Middleware {
    
    public typealias InputActionType = BluetoothAction
    public typealias OutputActionType = BluetoothAction
    public typealias StateType = BluetoothState
    
    private var getState: GetState<BluetoothState>?
    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private let peripheralDelegate = PeripheralManagerDelegate()
    private let centralDelegate = CentralManagerDelegate()

    public init() { }
    
    public func receiveContext(getState: @escaping GetState<BluetoothState>, output: AnyActionHandler<BluetoothAction>) {
        self.getState = getState
        
        peripheralDelegate.output = output
        peripheralDelegate.state = getState()
        centralDelegate.output = output
        centralDelegate.state = getState()
        
        peripheralManager = CBPeripheralManager(
            delegate: peripheralDelegate,
            queue: nil
        )
        
        centralManager = CBCentralManager(
            delegate: centralDelegate,
            queue: nil
        )
    }
    
    public func handle(action: BluetoothAction, from dispatcher: ActionSource, afterReducer: inout AfterReducer) {
        switch action {
        case let .request(.startAdvertising(advertisementData)): peripheralManager?.startAdvertising(advertisementData)
        case .request(.stopAdvertising): peripheralManager?.stopAdvertising()
        case let .request(.requestManagerState(type)):
            switch type {
            case .peripheral: peripheralDelegate.output?.dispatch(.status(.gotManagerState(.peripheral, peripheralManager?.state ?? .unknown)))
            case .central:
                centralDelegate.output?.dispatch(.status(.gotManagerState(.central, centralManager?.state ?? .unknown)))
            }
        default: return
        }
    }
}

// Service start / stop
extension CoreBluetoothMiddleware {
    func startService(service: BTManagerType) {
    }
    
    func stopService(service: BTManagerType) {

    }
}

// Device Capabilities
extension CoreBluetoothMiddleware {
//    func getDeviceCapabilities() -> StatusAction {
//
//    }
}

// Location Service Configuration
extension CoreBluetoothMiddleware {
//    func getLocationServiceConfig() -> StatusAction {
//    }
    
//    func setLocationServiceConfig(config: LocationServiceConfiguration) {
//    }
}


// MARK: - DELEGATE
class PeripheralManagerDelegate: NSObject, CBPeripheralManagerDelegate {
    
    var output: AnyActionHandler<BluetoothAction>? = nil
    var state: BluetoothState? = nil

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        output?.dispatch(.status(.gotManagerState(.peripheral, peripheral.state)))
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        output?.dispatch(.status(.gotStateRestoration(.peripheral, dict)))
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            output?.dispatch(.status(.receivedError(error)))
        } else {
            output?.dispatch(.status(.gotServiceAdditionAck(service)))
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            output?.dispatch(.status(.receivedError(error)))
        } else {
            output?.dispatch(.status(.gotAdvertisingAck))
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        output?.dispatch(.status(.gotSubscribedAck(central, characteristic)))
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        output?.dispatch(.status(.gotUnsubscribed(central, characteristic)))
    }
}

// MARK: - PRISM
extension BluetoothAction {
    public var status: StatusAction? {
        get {
            guard case let .status(value) = self else { return nil }
            return value
        }
        set {
            guard case .status = self, let newValue = newValue else { return }
            self = .status(newValue)
        }
    }

    public var isStatusAction: Bool {
        self.status != nil
    }
}


class CentralManagerDelegate: NSObject, CBCentralManagerDelegate {
    
    var output: AnyActionHandler<BluetoothAction>? = nil
    var state: BluetoothState? = nil

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        output?.dispatch(.status(.gotManagerState(.central, central.state)))
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        output?.dispatch(.status(.gotStateRestoration(.central, dict)))
    }
}
