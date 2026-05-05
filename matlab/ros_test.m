% ENGR 4550 Project - Live Kinematics Dashboard
clc; clear; close all;

% --- 1. Initialize ROS 2 Connection ---
disp('Connecting to ROS 2 Network...');
setenv('ROS_DOMAIN_ID', '0'); 
twinNode = ros2node("/matlab_kinematics_node");
jointSub = ros2subscriber(twinNode, "/joint_states", "sensor_msgs/JointState");
disp('Connected! Waiting for live data stream...');

% --- 2. Setup Dashboard Figure ---
fig = figure('Name', 'Live FANUC Kinematics', 'Color', 'w', 'Position', [100, 100, 1000, 800]);

% Setup colors and legends for 6 joints
colors = lines(6);
jointNames = {'J1', 'J2', 'J3', 'J4', 'J5', 'J6'};

% Subplot 1: Position
ax1 = subplot(3,1,1);
title('Joint Position (rad)');
ylabel('Position'); grid on; hold on;
for i = 1:6, posLines(i) = animatedline('Color', colors(i,:), 'LineWidth', 1.5, 'DisplayName', jointNames{i}); end
legend('Location', 'eastoutside');

% Subplot 2: Velocity
ax2 = subplot(3,1,2);
title('Joint Velocity (rad/s)');
ylabel('Velocity'); grid on; hold on;
for i = 1:6, velLines(i) = animatedline('Color', colors(i,:), 'LineWidth', 1.5); end

% Subplot 3: Acceleration
ax3 = subplot(3,1,3);
title('Joint Acceleration (rad/s^2)');
xlabel('Time (seconds)'); ylabel('Acceleration'); grid on; hold on;
for i = 1:6, accLines(i) = animatedline('Color', colors(i,:), 'LineWidth', 1.5); end

% --- 3. State Variables for Math ---
disp('Waiting for initial position to establish baseline...');
initialMsg = receive(jointSub, 10);
prev_pos = initialMsg.position';
prev_vel = zeros(1, 6);
prev_time = 0;

tic; % Start the relative clock

% --- 4. Live Data Loop ---
disp('Starting real-time graph stream. Close the figure window to stop.');
while isgraphics(fig)
    try
        % Pull newest message (0.5s timeout)
        msg = receive(jointSub, 0.5);
        
        % Current Data
        current_time = toc;
        current_pos = msg.position'; 
        
        % Math: Calculate dt, Velocity, and Acceleration
        dt = current_time - prev_time;
        
        if dt > 0
            % Vectorized math for all 6 joints simultaneously
            current_vel = (current_pos - prev_pos) / dt;
            current_acc = (current_vel - prev_vel) / dt;
            
            % Update Graph Points
            for i = 1:6
                addpoints(posLines(i), current_time, current_pos(i));
                addpoints(velLines(i), current_time, current_vel(i));
                addpoints(accLines(i), current_time, current_acc(i));
            end
            
            % Lock the X-axis to a rolling 5-second window
            xlim(ax1, [max(0, current_time-5), current_time]);
            xlim(ax2, [max(0, current_time-5), current_time]);
            xlim(ax3, [max(0, current_time-5), current_time]);
            
            % limitrate throttles the rendering frame rate to keep math prioritized
            drawnow limitrate; 
            
            % Store current state for the next loop
            prev_time = current_time;
            prev_pos = current_pos;
            prev_vel = current_vel;
        end
        
    catch ME
        if ~strcmp(ME.identifier, 'ros:mlros2:subscriber:WaitTimeout')
            disp('ERROR DETECTED:');
            disp(ME.message);
            break;
        end
    end
end
disp('Dashboard Terminated. Disconnecting from ROS network.');
clear twinNode;