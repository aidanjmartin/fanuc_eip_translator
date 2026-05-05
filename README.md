# fanuc_eip_translator

A ROS 2 Python node that acts as a real-time EtherNet/IP bridge between a **FANUC CRX-20iA/L** robot controller and a ROS 2 topic. It reads live joint positions from the robot at 20 Hz and publishes them as standard `sensor_msgs/JointState` messages, making the robot's state available to any ROS 2-compatible client on the local network — including a remote MATLAB Kinematics Dashboard.

---

## System Architecture

```
┌─────────────────────────────┐          LAN Switch (192.168.1.x)
│  FANUC CRX-20iA/L           │◄────────────────────────────────────┐
│  Controller                 │  EtherNet/IP / CIP (port 44818)     │
│  IP: 192.168.1.155          │  Class 0x7E (CurJpos), 20 Hz        │
└─────────────────────────────┘                                      │
                                                          ┌──────────┴──────────┐
                                                          │  Ubuntu PC          │
                                                          │  (This package)     │
                                                          │  IP: 192.168.1.xxx  │
                                                          │                     │
                                                          │  ROS 2 Node:        │
                                                          │  fanuc_eip_trans-   │
                                                          │  lator              │
                                                          │  ↓ publishes        │
                                                          │  /joint_states      │
                                                          └──────────┬──────────┘
                                                                     │
                                                          ROS 2 DDS (UDP multicast)
                                                          ROS_DOMAIN_ID = 0
                                                                     │
                                                          ┌──────────┴──────────┐
                                                          │  MATLAB Laptop      │
                                                          │  ROS Toolbox        │
                                                          │  Subscribes to      │
                                                          │  /joint_states      │
                                                          │  ↓                  │
                                                          │  Kinematics         │
                                                          │  Dashboard          │
                                                          └─────────────────────┘
```

### Data Flow Summary

1. The ROS 2 node opens a persistent CIP connection to the robot controller over EtherNet/IP.
2. A 20 Hz timer fires `generic_message` requests using **CIP service `0x0E` (Get Attribute Single)** against **Class `0x7E` (CurJpos)**, Instance 1, Attribute 1.
3. The raw CIP response payload is unpacked as `<hhfffffffff` (2 signed shorts + 9 floats): the first two shorts are `uframe` and `utool` indices; floats 0–8 are joint angles J1–J9 in **degrees**.
4. J1–J6 are converted to **radians** and published as a `sensor_msgs/JointState` message on `/joint_states`.
5. Any ROS 2 node or client sharing the same `ROS_DOMAIN_ID` on the LAN receives the topic via DDS discovery.

---

## Dependencies

### ROS 2

This package targets **ROS 2 Humble** (Ubuntu 22.04) or later. Install the full desktop variant:

```bash
sudo apt install ros-humble-desktop
```

### Python — pycomm3

`pycomm3` is a pure-Python EtherNet/IP / CIP library used to communicate with the FANUC controller. It is **not** managed by `rosdep` and must be installed manually:

```bash
pip install pycomm3
```

### ROS 2 message packages

Both are included in `ros-humble-desktop`. If using a minimal install:

```bash
sudo apt install ros-humble-rclpy ros-humble-sensor-msgs
```

---

## Network Setup

### Static IP on the Ubuntu PC

The FANUC controller is preconfigured at `192.168.1.155`. The Ubuntu machine must be on the same `/24` subnet.

1. Open **Settings → Network** (or use `nmcli`).
2. Set the Ethernet interface connected to the LAN switch to a static address, for example:
   - **IP Address:** `192.168.1.100`
   - **Subnet Mask:** `255.255.255.0`
   - **Gateway:** (leave blank or use `192.168.1.1`)
3. Verify connectivity:
   ```bash
   ping 192.168.1.155
   ```

### Static IP on the MATLAB Laptop

Set the MATLAB laptop's Ethernet interface to another address on the same subnet, for example:
- **IP Address:** `192.168.1.101`
- **Subnet Mask:** `255.255.255.0`

### ROS_DOMAIN_ID

Both machines must share the same domain ID. The default (`0`) is used here. Add the following to `~/.bashrc` on **both** the Ubuntu PC and the MATLAB laptop's ROS environment:

```bash
export ROS_DOMAIN_ID=0
```

On the Ubuntu PC also source the ROS installation:

```bash
source /opt/ros/humble/setup.bash
```

DDS multicast must not be blocked by the switch or any host firewall. If discovery fails, confirm with:

```bash
ros2 topic list   # run from the MATLAB laptop's terminal
```

---

## Build

```bash
cd ~/ros2_ws
source /opt/ros/humble/setup.bash
colcon build --packages-select fanuc_eip_translator
source install/setup.bash
```

---

## Run

```bash
ros2 run fanuc_eip_translator eip_node
```

Expected output once the robot is reachable:

```
[INFO] [fanuc_eip_translator]: Connected to CRX-20iA/L at 192.168.1.155...
```

Verify the topic is publishing:

```bash
ros2 topic echo /joint_states
ros2 topic hz /joint_states    # should report ~20 Hz
```

---

## MATLAB Kinematics Dashboard

### Connecting the MATLAB ROS Toolbox

On the MATLAB laptop, install the **ROS Toolbox** (MathWorks Add-On Explorer). No ROS master is required for ROS 2 — the toolbox uses DDS directly.

Initialize a ROS 2 node in MATLAB:

```matlab
node = ros2node('/matlab_kinematics_client');
sub  = ros2subscriber(node, '/joint_states', 'sensor_msgs/JointState', @kinematicsCallback);
```

Because `ROS_DOMAIN_ID=0` is set on both machines and both are on the `192.168.1.x` subnet, DDS will discover the Ubuntu publisher automatically within a few seconds.

### Data Handoff

Each `sensor_msgs/JointState` message delivered to the callback contains:

| Field | Type | Content |
|---|---|---|
| `header.stamp` | `builtin_interfaces/Time` | ROS clock timestamp of the sample |
| `name` | `string[6]` | `['J1','J2','J3','J4','J5','J6']` |
| `position` | `float64[6]` | Joint angles in **radians** |
| `velocity` | `float64[]` | Empty (not populated by this node) |
| `effort` | `float64[]` | Empty (not populated by this node) |

### Kinematics Dashboard Concept

Because the node provides a continuous, timestamped position stream at 20 Hz, the MATLAB client can derive higher-order kinematics entirely in software:

**Velocity** — finite difference on consecutive position samples:

```matlab
omega = (q_now - q_prev) / dt;   % rad/s per joint
```

**Acceleration** — second finite difference:

```matlab
alpha = (omega_now - omega_prev) / dt;   % rad/s² per joint
```

The Dashboard typically presents:
- **Live joint angle plots** (6 time series)
- **Per-joint velocity** (deg/s or rad/s)
- **Per-joint acceleration** (deg/s² or rad/s²)
- Optional: **Cartesian end-effector velocity** derived from the robot's Jacobian

Because all computation happens on the MATLAB side and the ROS 2 node only publishes raw positions, the bridge remains stateless and the dashboard logic can be iterated without touching the ROS 2 package.

---

## Package Structure

```
fanuc_eip_translator/
├── fanuc_eip_translator/
│   ├── __init__.py
│   ├── eip_translator_node.py   # ROS 2 node implementation
│   └── py.typed
├── resource/
│   └── fanuc_eip_translator
├── test/
│   ├── test_copyright.py
│   ├── test_flake8.py
│   ├── test_mypy.py
│   ├── test_pep257.py
│   └── test_xmllint.py
├── package.xml
├── setup.cfg
├── setup.py
└── README.md
```

---

## License

MIT
