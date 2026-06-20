#!/usr/bin/env python3
"""가상로봇 시뮬 백엔드 B — 기존 piper_gazebo(ros2_control) 직결.

확인된 인터페이스 (piper_ros/src/piper_sim/piper_gazebo):
  - 명령: /arm_controller/joint_trajectory  (trajectory_msgs/JointTrajectory, joint1~6, position)
  - 상태: /joint_states                     (sensor_msgs/JointState, rad)
ros2_controllers.yaml: arm_controller = JointTrajectoryController, 500Hz.

컨테이너(piper-hil:humble) 안에서 ROS2 환경 소싱 후 실행. rclpy 는 지연 임포트.
"""


class GazeboBackend:
    def __init__(self, joint_names=None, traj_time: float = 0.1):
        import rclpy
        from rclpy.node import Node
        from sensor_msgs.msg import JointState
        from trajectory_msgs.msg import JointTrajectory, JointTrajectoryPoint
        self._rclpy = rclpy
        self._JointTrajectory = JointTrajectory
        self._JointTrajectoryPoint = JointTrajectoryPoint
        self.joint_names = joint_names or [f"joint{i}" for i in range(1, 7)]
        self.traj_time = traj_time

        if not rclpy.ok():
            rclpy.init()
        self.node = Node("piper_virtual_robot")
        self.pub = self.node.create_publisher(
            JointTrajectory, "/arm_controller/joint_trajectory", 10)
        self.state = [0.0] * 6
        self.enabled = False
        self.node.create_subscription(JointState, "/joint_states", self._on_state, 10)

    def _on_state(self, msg):
        idx = {n: i for i, n in enumerate(msg.name)}
        for k, jn in enumerate(self.joint_names):
            if jn in idx and idx[jn] < len(msg.position):
                self.state[k] = msg.position[idx[jn]]

    def set_targets(self, rad6):
        if not self.enabled:
            return
        traj = self._JointTrajectory()
        traj.joint_names = list(self.joint_names)
        pt = self._JointTrajectoryPoint()
        pt.positions = [float(x) for x in rad6]
        sec = int(self.traj_time)
        pt.time_from_start.sec = sec
        pt.time_from_start.nanosec = int((self.traj_time - sec) * 1e9)
        traj.points = [pt]
        self.pub.publish(traj)

    def set_enable(self, on: bool):
        self.enabled = on

    def get_state(self):
        return list(self.state)

    def spin_once(self, dt: float):
        self._rclpy.spin_once(self.node, timeout_sec=0.0)

    def close(self):
        self.node.destroy_node()
        if self._rclpy.ok():
            self._rclpy.shutdown()
