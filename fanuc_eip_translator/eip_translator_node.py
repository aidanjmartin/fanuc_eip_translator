#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import JointState
import math
import struct
from pycomm3 import CIPDriver


class FanucEipTranslator(Node):
    def __init__(self):
        super().__init__('fanuc_eip_translator')
        self.publisher_ = self.create_publisher(JointState, '/joint_states', 10)

        self.robot_ip = '192.168.1.155'
        self.robot = CIPDriver(self.robot_ip)
        self.robot.open()
        self.get_logger().info(f'Connected to CRX-20iA/L at {self.robot_ip}...')

        self.timer = self.create_timer(0.05, self.timer_callback)

    def timer_callback(self):
        msg = JointState()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.name = ['J1', 'J2', 'J3', 'J4', 'J5', 'J6']

        try:
            response = self.robot.generic_message(
                service=0x0e,
                class_code=0x7e,
                instance=1,
                attribute=1
            )

            if response and response.value:
                # CurJpos payload: 2 shorts (uframe, utool) + 9 floats (J1-J9)
                pos_struct = struct.unpack('<hhfffffffff', response.value)

                # Indices 2-7 are J1-J6; FANUC reports degrees, ROS expects radians
                msg.position = [
                    math.radians(pos_struct[2]),
                    math.radians(pos_struct[3]),
                    math.radians(pos_struct[4]),
                    math.radians(pos_struct[5]),
                    math.radians(pos_struct[6]),
                    math.radians(pos_struct[7])
                ]

                self.publisher_.publish(msg)

        except Exception as e:
            self.get_logger().error(f'Data read failed: {e}')


def main(args=None):
    rclpy.init(args=args)
    node = FanucEipTranslator()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.robot.close()
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()