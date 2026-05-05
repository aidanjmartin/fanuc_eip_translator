from setuptools import find_packages, setup

package_name = 'fanuc_eip_translator'

setup(
    name=package_name,
    version='1.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    package_data={'': ['py.typed']},
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='aidanjmartin',
    maintainer_email='aidanm3814@gmail.com',
    description='ROS 2 EtherNet/IP bridge node for the FANUC CRX-20iA/L robot controller.',
    license='MIT',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'eip_node = fanuc_eip_translator.eip_translator_node:main'
        ],
    },
)
